-- =====================================================================
-- SOH Assessment™ — Esquema de banco de dados v3 (Supabase / PostgreSQL)
-- =====================================================================
-- Arquitetura relacional completa: participants, assessments, questions,
-- answers, domain_scores, subdomain_scores, results, recommendations.
--
-- Este script SUBSTITUI a versão anterior (que usava assessment_domains,
-- assessment_subdomains, assessment_answers, assessment_results).
-- É seguro rodar mesmo que a versão anterior já exista no seu projeto:
-- as tabelas antigas são removidas e recriadas com a nova estrutura.
--
-- Como aplicar:
--   1. app.supabase.com → seu projeto → SQL Editor → New query
--   2. Cole este arquivo inteiro → Run
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0. LIMPEZA DA ARQUITETURA ANTERIOR (v1)
-- ---------------------------------------------------------------------
drop table if exists public.assessment_results cascade;
drop table if exists public.assessment_answers cascade;
drop table if exists public.assessment_subdomains cascade;
drop table if exists public.assessment_domains cascade;

-- ---------------------------------------------------------------------
-- 1. PARTICIPANTS — dados de cadastro do participante
-- ---------------------------------------------------------------------
create table if not exists public.participants (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  assessment_date  date not null default current_date,
  assessment_time  time not null default current_time,
  nome             text not null,
  email            text,
  telefone         text,
  empresa          text,
  cargo            text,
  cidade           text,
  estado           text,
  sexo             text,
  idade            smallint,
  estado_civil     text,
  escolaridade     text,
  facilitador      text,
  programa         text,
  observacoes      text
);

-- Garante as colunas mesmo que a tabela já existisse de uma versão anterior
alter table public.participants add column if not exists email    text;
alter table public.participants add column if not exists telefone text;
alter table public.participants add column if not exists empresa  text;
alter table public.participants add column if not exists cargo    text;
alter table public.participants add column if not exists estado   text;

comment on table public.participants is 'Cadastro do participante que respondeu ao SOH Assessment™.';

-- ---------------------------------------------------------------------
-- 2. QUESTIONS — banco de questões oficial (dado de referência)
-- ---------------------------------------------------------------------
-- Tabela de apoio/relacional: garante integridade referencial das
-- respostas e permite versionar o instrumento no futuro (v5.0, v5.1...)
-- sem remodelar o banco. É semeada uma única vez (ver seed abaixo) e
-- não é alterada pelo aplicativo em tempo de execução.
create table if not exists public.questions (
  id                smallint not null,
  instrument_version text not null default 'v5.0',
  domain_name       text not null,
  domain_order      smallint not null check (domain_order between 1 and 12),
  subdomain_name    text not null,
  subdomain_order   smallint not null check (subdomain_order between 1 and 6),
  question_text     text not null,
  primary key (id, instrument_version)
);

comment on table public.questions is 'Banco oficial das 288 questões do SOH Assessment™, por versão do instrumento.';

-- ---------------------------------------------------------------------
-- 3. ASSESSMENTS — uma aplicação completa do instrumento
-- ---------------------------------------------------------------------
create table if not exists public.assessments (
  id                    uuid primary key default gen_random_uuid(),
  participant_id        uuid not null references public.participants(id) on delete cascade,
  instrument_version    text not null default 'v5.0',
  started_at            timestamptz not null,
  completed_at          timestamptz not null default now(),
  duration_seconds      integer,
  igsoh                 numeric(4,2) not null check (igsoh between 1 and 5),
  igsoh_classification  text not null,
  ics                   numeric(4,2) not null check (ics between 1 and 5),
  itp                   numeric(4,2) not null check (itp between 1 and 5),
  ire                   numeric(4,2) not null check (ire between 1 and 5),
  iei                   numeric(4,2) not null check (iei between 1 and 5),
  cpt_domain            text not null,
  cpt_score             numeric(4,2) not null,
  status                text not null default 'completed'
);

alter table public.assessments add column if not exists instrument_version text not null default 'v5.0';

comment on table public.assessments is 'Resultado consolidado de uma aplicação do SOH Assessment™ (288 questões).';

-- ---------------------------------------------------------------------
-- 4. ANSWERS — as 288 respostas individuais (normalizadas via FK)
-- ---------------------------------------------------------------------
create table if not exists public.answers (
  id                  uuid primary key default gen_random_uuid(),
  assessment_id       uuid not null references public.assessments(id) on delete cascade,
  question_id         smallint not null,
  instrument_version  text not null default 'v5.0',
  answer_value        smallint not null check (answer_value between 1 and 5),
  foreign key (question_id, instrument_version) references public.questions(id, instrument_version)
);

-- ---------------------------------------------------------------------
-- 5. DOMAIN_SCORES — pontuação dos 12 domínios
-- ---------------------------------------------------------------------
create table if not exists public.domain_scores (
  id              uuid primary key default gen_random_uuid(),
  assessment_id   uuid not null references public.assessments(id) on delete cascade,
  domain_name     text not null,
  domain_order    smallint not null check (domain_order between 1 and 12),
  score           numeric(4,2) not null check (score between 1 and 5),
  classification  text not null
);

-- ---------------------------------------------------------------------
-- 6. SUBDOMAIN_SCORES — pontuação dos 72 subdomínios (12 x 6)
-- ---------------------------------------------------------------------
create table if not exists public.subdomain_scores (
  id                uuid primary key default gen_random_uuid(),
  assessment_id     uuid not null references public.assessments(id) on delete cascade,
  domain_name       text not null,
  subdomain_name    text not null,
  subdomain_order   smallint not null check (subdomain_order between 1 and 6),
  score             numeric(4,2) not null check (score between 1 and 5)
);

-- ---------------------------------------------------------------------
-- 7. RESULTS — visão geral: radar, macrodimensões, interpretações
-- ---------------------------------------------------------------------
create table if not exists public.results (
  id                   uuid primary key default gen_random_uuid(),
  assessment_id        uuid not null unique references public.assessments(id) on delete cascade,
  radar_data           jsonb not null,   -- [{domain, score}, ...] — os 12 pontos do radar
  macrodimensions      jsonb not null,   -- [{name, score}, ...] — as 4 macrodimensões
  interpretations      jsonb not null,   -- texto explicativo de cada índice (IGSOH/ICS/ITP/IRE/IEI)
  pontos_fortes        jsonb not null,
  pontos_vulneraveis   jsonb not null,
  created_at           timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 8. RECOMMENDATIONS — plano de ação (PEDI™), uma linha por domínio
-- ---------------------------------------------------------------------
create table if not exists public.recommendations (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null references public.assessments(id) on delete cascade,
  prioridade     smallint not null,
  domain_name    text not null,
  score          numeric(4,2) not null,
  classification text not null,
  protocolo      text not null,
  nivel          text not null,   -- '1 - Obrigatório' | '2 - Complementar' | '3 - Manutenção'
  prazo          text not null,
  status         text
);

-- =====================================================================
-- ÍNDICES DE DESEMPENHO
-- =====================================================================
create index if not exists idx_assessments_participant     on public.assessments(participant_id);
create index if not exists idx_assessments_completed_at     on public.assessments(completed_at desc);
create index if not exists idx_answers_assessment           on public.answers(assessment_id);
create index if not exists idx_answers_question              on public.answers(question_id, instrument_version);
create index if not exists idx_domain_scores_assessment      on public.domain_scores(assessment_id);
create index if not exists idx_subdomain_scores_assessment   on public.subdomain_scores(assessment_id);
create index if not exists idx_recommendations_assessment    on public.recommendations(assessment_id);
create index if not exists idx_participants_nome             on public.participants using gin (to_tsvector('portuguese', nome));

-- =====================================================================
-- ROW LEVEL SECURITY (RLS)
-- =====================================================================
-- Modelo de segurança (single-tenant, sem login de facilitador):
--   - A chave usada no navegador é a "publishable" (anon/pública).
--   - Ela pode INSERIR dados em todas as tabelas de gravação.
--   - Ela pode LER apenas a tabela "questions" (dado de referência,
--     não sensível — é o próprio enunciado das perguntas).
--   - Ela NÃO pode ler, alterar ou apagar dados de participantes,
--     respostas ou resultados. Isso impede que alguém com acesso ao
--     código público do GitHub Pages consiga ler dados de outros
--     participantes.
--   - Para consultar os resultados depois, use o SQL Editor / Table
--     Editor do Supabase Studio (autenticado com sua conta).
-- =====================================================================

alter table public.participants       enable row level security;
alter table public.questions          enable row level security;
alter table public.assessments        enable row level security;
alter table public.answers            enable row level security;
alter table public.domain_scores      enable row level security;
alter table public.subdomain_scores   enable row level security;
alter table public.results            enable row level security;
alter table public.recommendations    enable row level security;

-- Leitura pública do banco de questões (não sensível)
drop policy if exists "anon_select_questions" on public.questions;
create policy "anon_select_questions"
  on public.questions for select
  to anon
  using (true);

-- Gravação (somente INSERT) nas demais tabelas
drop policy if exists "anon_insert_participants" on public.participants;
create policy "anon_insert_participants"
  on public.participants for insert to anon with check (true);

drop policy if exists "anon_insert_assessments" on public.assessments;
create policy "anon_insert_assessments"
  on public.assessments for insert to anon with check (true);

drop policy if exists "anon_insert_answers" on public.answers;
create policy "anon_insert_answers"
  on public.answers for insert to anon with check (true);

drop policy if exists "anon_insert_domain_scores" on public.domain_scores;
create policy "anon_insert_domain_scores"
  on public.domain_scores for insert to anon with check (true);

drop policy if exists "anon_insert_subdomain_scores" on public.subdomain_scores;
create policy "anon_insert_subdomain_scores"
  on public.subdomain_scores for insert to anon with check (true);

drop policy if exists "anon_insert_results" on public.results;
create policy "anon_insert_results"
  on public.results for insert to anon with check (true);

drop policy if exists "anon_insert_recommendations" on public.recommendations;
create policy "anon_insert_recommendations"
  on public.recommendations for insert to anon with check (true);

-- Nenhuma política de SELECT/UPDATE/DELETE é criada para "anon" nas
-- tabelas acima (exceto "questions"): por padrão, com RLS habilitado
-- e sem política correspondente, o PostgreSQL nega o acesso.

-- =====================================================================
-- SEED — banco oficial das 288 questões (v5.0)
-- =====================================================================
-- Seed do banco de questões oficial do SOH Assessment™ (v5.0) — 288 itens
insert into public.questions (id, instrument_version, domain_name, domain_order, subdomain_name, subdomain_order, question_text) values
(1, 'v5.0', 'Identidade', 1, 'Autoimagem', 1, 'Tenho uma percepção positiva de mim mesmo.'),
(2, 'v5.0', 'Identidade', 1, 'Autoimagem', 1, 'Reconheço minhas qualidades pessoais.'),
(3, 'v5.0', 'Identidade', 1, 'Autoimagem', 1, 'Estou satisfeito com a pessoa que sou.'),
(4, 'v5.0', 'Identidade', 1, 'Autoimagem', 1, 'Minha autoimagem favorece meu desenvolvimento.'),
(5, 'v5.0', 'Identidade', 1, 'Autoconceito', 2, 'Compreendo claramente minhas características pessoais.'),
(6, 'v5.0', 'Identidade', 1, 'Autoconceito', 2, 'Sei identificar meus pontos fortes.'),
(7, 'v5.0', 'Identidade', 1, 'Autoconceito', 2, 'Reconheço minhas limitações sem perder a confiança.'),
(8, 'v5.0', 'Identidade', 1, 'Autoconceito', 2, 'Tenho clareza sobre minhas capacidades.'),
(9, 'v5.0', 'Identidade', 1, 'Autovalor', 3, 'Considero que tenho valor independentemente das circunstâncias.'),
(10, 'v5.0', 'Identidade', 1, 'Autovalor', 3, 'Trato-me com respeito.'),
(11, 'v5.0', 'Identidade', 1, 'Autovalor', 3, 'Não dependo exclusivamente da aprovação dos outros para sentir meu valor.'),
(12, 'v5.0', 'Identidade', 1, 'Autovalor', 3, 'Reconheço minha dignidade pessoal.'),
(13, 'v5.0', 'Identidade', 1, 'Coerência', 4, 'Minhas atitudes refletem aquilo em que acredito.'),
(14, 'v5.0', 'Identidade', 1, 'Coerência', 4, 'Procuro agir de acordo com meus princípios.'),
(15, 'v5.0', 'Identidade', 1, 'Coerência', 4, 'Existe coerência entre minhas palavras e ações.'),
(16, 'v5.0', 'Identidade', 1, 'Coerência', 4, 'Busco viver de forma íntegra.'),
(17, 'v5.0', 'Identidade', 1, 'Propósito Pessoal', 5, 'Tenho clareza sobre a direção da minha vida.'),
(18, 'v5.0', 'Identidade', 1, 'Propósito Pessoal', 5, 'Meus objetivos refletem quem eu sou.'),
(19, 'v5.0', 'Identidade', 1, 'Propósito Pessoal', 5, 'Meu propósito orienta minhas decisões.'),
(20, 'v5.0', 'Identidade', 1, 'Propósito Pessoal', 5, 'Sei por que faço o que faço.'),
(21, 'v5.0', 'Identidade', 1, 'Identidade Espiritual', 6, 'Minha identidade espiritual influencia minhas decisões.'),
(22, 'v5.0', 'Identidade', 1, 'Identidade Espiritual', 6, 'Compreendo meu valor diante de Deus.'),
(23, 'v5.0', 'Identidade', 1, 'Identidade Espiritual', 6, 'Procuro viver coerentemente com meus princípios espirituais.'),
(24, 'v5.0', 'Identidade', 1, 'Identidade Espiritual', 6, 'Minha espiritualidade fortalece minha identidade.'),
(25, 'v5.0', 'Paradigmas', 2, 'Paradigmas Limitantes', 1, 'Identifico crenças que limitam meu desenvolvimento.'),
(26, 'v5.0', 'Paradigmas', 2, 'Paradigmas Limitantes', 1, 'Questiono ideias negativas que mantenho sobre mim.'),
(27, 'v5.0', 'Paradigmas', 2, 'Paradigmas Limitantes', 1, 'Estou disposto a substituir paradigmas improdutivos.'),
(28, 'v5.0', 'Paradigmas', 2, 'Paradigmas Limitantes', 1, 'Percebo quando pensamentos antigos influenciam minhas decisões.'),
(29, 'v5.0', 'Paradigmas', 2, 'Flexibilidade Cognitiva', 2, 'Considero novas perspectivas antes de concluir.'),
(30, 'v5.0', 'Paradigmas', 2, 'Flexibilidade Cognitiva', 2, 'Estou aberto a aprender com opiniões diferentes.'),
(31, 'v5.0', 'Paradigmas', 2, 'Flexibilidade Cognitiva', 2, 'Adapto minhas crenças quando encontro evidências melhores.'),
(32, 'v5.0', 'Paradigmas', 2, 'Flexibilidade Cognitiva', 2, 'Consigo rever minhas convicções sem perder minha identidade.'),
(33, 'v5.0', 'Paradigmas', 2, 'Aprendizagem', 3, 'Busco continuamente novos conhecimentos.'),
(34, 'v5.0', 'Paradigmas', 2, 'Aprendizagem', 3, 'Transformo conhecimento em prática.'),
(35, 'v5.0', 'Paradigmas', 2, 'Aprendizagem', 3, 'Aprendo com meus erros.'),
(36, 'v5.0', 'Paradigmas', 2, 'Aprendizagem', 3, 'Tenho curiosidade para desenvolver novas competências.'),
(37, 'v5.0', 'Paradigmas', 2, 'Responsabilidade', 4, 'Assumo responsabilidade pelos meus resultados.'),
(38, 'v5.0', 'Paradigmas', 2, 'Responsabilidade', 4, 'Evito culpar circunstâncias ou pessoas.'),
(39, 'v5.0', 'Paradigmas', 2, 'Responsabilidade', 4, 'Reconheço meu papel nas situações que vivo.'),
(40, 'v5.0', 'Paradigmas', 2, 'Responsabilidade', 4, 'Procuro agir em vez de reclamar.'),
(41, 'v5.0', 'Paradigmas', 2, 'Crescimento', 5, 'Acredito que posso evoluir continuamente.'),
(42, 'v5.0', 'Paradigmas', 2, 'Crescimento', 5, 'Vejo desafios como oportunidades de crescimento.'),
(43, 'v5.0', 'Paradigmas', 2, 'Crescimento', 5, 'Persisto mesmo diante de dificuldades.'),
(44, 'v5.0', 'Paradigmas', 2, 'Crescimento', 5, 'Invisto regularmente em meu desenvolvimento.'),
(45, 'v5.0', 'Paradigmas', 2, 'Visão de Mundo', 6, 'Minha forma de ver o mundo favorece meu crescimento.'),
(46, 'v5.0', 'Paradigmas', 2, 'Visão de Mundo', 6, 'Procuro interpretar situações de forma construtiva.'),
(47, 'v5.0', 'Paradigmas', 2, 'Visão de Mundo', 6, 'Meus paradigmas fortalecem meus relacionamentos.'),
(48, 'v5.0', 'Paradigmas', 2, 'Visão de Mundo', 6, 'Meus paradigmas contribuem para meu propósito de vida.'),
(49, 'v5.0', 'Programação Mental', 3, 'Subdomínio 1', 1, 'Meus pensamentos influenciam diretamente meus comportamentos.'),
(50, 'v5.0', 'Programação Mental', 3, 'Subdomínio 1', 1, 'Tenho consciência dos pensamentos que repito diariamente.'),
(51, 'v5.0', 'Programação Mental', 3, 'Subdomínio 1', 1, 'Substituo pensamentos negativos por interpretações mais úteis.'),
(52, 'v5.0', 'Programação Mental', 3, 'Subdomínio 1', 1, 'Procuro alimentar minha mente com informações construtivas.'),
(53, 'v5.0', 'Programação Mental', 3, 'Subdomínio 2', 2, 'Percebo quando pensamentos automáticos prejudicam meu desempenho.'),
(54, 'v5.0', 'Programação Mental', 3, 'Subdomínio 2', 2, 'Questiono crenças que limitam meu crescimento.'),
(55, 'v5.0', 'Programação Mental', 3, 'Subdomínio 2', 2, 'Tenho controle sobre o foco da minha atenção.'),
(56, 'v5.0', 'Programação Mental', 3, 'Subdomínio 2', 2, 'Evito alimentar pensamentos improdutivos.'),
(57, 'v5.0', 'Programação Mental', 3, 'Subdomínio 3', 3, 'Minhas decisões refletem pensamentos bem estruturados.'),
(58, 'v5.0', 'Programação Mental', 3, 'Subdomínio 3', 3, 'Cultivo pensamentos coerentes com meus objetivos.'),
(59, 'v5.0', 'Programação Mental', 3, 'Subdomínio 3', 3, 'Visualizo mentalmente os resultados que desejo alcançar.'),
(60, 'v5.0', 'Programação Mental', 3, 'Subdomínio 3', 3, 'Utilizo a repetição para fortalecer novos padrões mentais.'),
(61, 'v5.0', 'Programação Mental', 3, 'Subdomínio 4', 4, 'Reconheço quando estou preso a padrões antigos de pensamento.'),
(62, 'v5.0', 'Programação Mental', 3, 'Subdomínio 4', 4, 'Sou intencional ao desenvolver uma mentalidade positiva.'),
(63, 'v5.0', 'Programação Mental', 3, 'Subdomínio 4', 4, 'Minhas conversas internas favorecem meu desenvolvimento.'),
(64, 'v5.0', 'Programação Mental', 3, 'Subdomínio 4', 4, 'Minha programação mental fortalece minha autoconfiança.'),
(65, 'v5.0', 'Programação Mental', 3, 'Subdomínio 5', 5, 'Tenho facilidade para aprender novos padrões mentais.'),
(66, 'v5.0', 'Programação Mental', 3, 'Subdomínio 5', 5, 'Persisto até consolidar novas formas de pensar.'),
(67, 'v5.0', 'Programação Mental', 3, 'Subdomínio 5', 5, 'Meus pensamentos estão alinhados aos meus valores.'),
(68, 'v5.0', 'Programação Mental', 3, 'Subdomínio 5', 5, 'Minha programação mental favorece minha realização.'),
(69, 'v5.0', 'Programação Mental', 3, 'Subdomínio 6', 6, 'Percebo evolução na qualidade dos meus pensamentos.'),
(70, 'v5.0', 'Programação Mental', 3, 'Subdomínio 6', 6, 'Consigo interromper padrões mentais destrutivos.'),
(71, 'v5.0', 'Programação Mental', 3, 'Subdomínio 6', 6, 'Minha mente trabalha a favor dos meus objetivos.'),
(72, 'v5.0', 'Programação Mental', 3, 'Subdomínio 6', 6, 'Invisto continuamente no fortalecimento da minha programação mental.'),
(73, 'v5.0', 'Consciência', 4, 'Subdomínio 1', 1, 'Percebo meus pensamentos antes de agir.'),
(74, 'v5.0', 'Consciência', 4, 'Subdomínio 1', 1, 'Reconheço minhas emoções com facilidade.'),
(75, 'v5.0', 'Consciência', 4, 'Subdomínio 1', 1, 'Identifico os fatores que influenciam minhas decisões.'),
(76, 'v5.0', 'Consciência', 4, 'Subdomínio 1', 1, 'Reflito sobre minhas atitudes regularmente.'),
(77, 'v5.0', 'Consciência', 4, 'Subdomínio 2', 2, 'Tenho consciência dos meus pontos fortes.'),
(78, 'v5.0', 'Consciência', 4, 'Subdomínio 2', 2, 'Reconheço minhas limitações sem resistência.'),
(79, 'v5.0', 'Consciência', 4, 'Subdomínio 2', 2, 'Aceito feedback de forma construtiva.'),
(80, 'v5.0', 'Consciência', 4, 'Subdomínio 2', 2, 'Busco aprender com meus erros.'),
(81, 'v5.0', 'Consciência', 4, 'Subdomínio 3', 3, 'Percebo padrões repetitivos em meu comportamento.'),
(82, 'v5.0', 'Consciência', 4, 'Subdomínio 3', 3, 'Identifico gatilhos emocionais.'),
(83, 'v5.0', 'Consciência', 4, 'Subdomínio 3', 3, 'Compreendo como minhas escolhas afetam outras pessoas.'),
(84, 'v5.0', 'Consciência', 4, 'Subdomínio 3', 3, 'Avalio as consequências antes de decidir.'),
(85, 'v5.0', 'Consciência', 4, 'Subdomínio 4', 4, 'Consigo distinguir fatos de interpretações.'),
(86, 'v5.0', 'Consciência', 4, 'Subdomínio 4', 4, 'Questiono crenças automáticas.'),
(87, 'v5.0', 'Consciência', 4, 'Subdomínio 4', 4, 'Analiso minhas motivações.'),
(88, 'v5.0', 'Consciência', 4, 'Subdomínio 4', 4, 'Procuro agir de forma intencional.'),
(89, 'v5.0', 'Consciência', 4, 'Subdomínio 5', 5, 'Tenho clareza sobre minhas prioridades.'),
(90, 'v5.0', 'Consciência', 4, 'Subdomínio 5', 5, 'Avalio meu progresso regularmente.'),
(91, 'v5.0', 'Consciência', 4, 'Subdomínio 5', 5, 'Sei quando preciso mudar de estratégia.'),
(92, 'v5.0', 'Consciência', 4, 'Subdomínio 5', 5, 'Busco alinhar ações aos meus objetivos.'),
(93, 'v5.0', 'Consciência', 4, 'Subdomínio 6', 6, 'Reservo tempo para autorreflexão.'),
(94, 'v5.0', 'Consciência', 4, 'Subdomínio 6', 6, 'Aprendo com minhas experiências.'),
(95, 'v5.0', 'Consciência', 4, 'Subdomínio 6', 6, 'Assumo responsabilidade pelo meu desenvolvimento.'),
(96, 'v5.0', 'Consciência', 4, 'Subdomínio 6', 6, 'Transformo consciência em ação.'),
(97, 'v5.0', 'Mentalidade', 5, 'Subdomínio 1', 1, 'Tenho uma visão positiva sobre meu futuro.'),
(98, 'v5.0', 'Mentalidade', 5, 'Subdomínio 1', 1, 'Acredito que posso desenvolver novas competências.'),
(99, 'v5.0', 'Mentalidade', 5, 'Subdomínio 1', 1, 'Encaro desafios como oportunidades de crescimento.'),
(100, 'v5.0', 'Mentalidade', 5, 'Subdomínio 1', 1, 'Persisto diante das dificuldades.'),
(101, 'v5.0', 'Mentalidade', 5, 'Subdomínio 2', 2, 'Assumo responsabilidade pelos meus resultados.'),
(102, 'v5.0', 'Mentalidade', 5, 'Subdomínio 2', 2, 'Mantenho foco em soluções em vez de problemas.'),
(103, 'v5.0', 'Mentalidade', 5, 'Subdomínio 2', 2, 'Tenho confiança para enfrentar mudanças.'),
(104, 'v5.0', 'Mentalidade', 5, 'Subdomínio 2', 2, 'Busco melhorar continuamente.'),
(105, 'v5.0', 'Mentalidade', 5, 'Subdomínio 3', 3, 'Defino metas desafiadoras e realistas.'),
(106, 'v5.0', 'Mentalidade', 5, 'Subdomínio 3', 3, 'Acredito que esforço gera progresso.'),
(107, 'v5.0', 'Mentalidade', 5, 'Subdomínio 3', 3, 'Aprendo com os fracassos.'),
(108, 'v5.0', 'Mentalidade', 5, 'Subdomínio 3', 3, 'Evito pensamentos autolimitantes.'),
(109, 'v5.0', 'Mentalidade', 5, 'Subdomínio 4', 4, 'Cultivo atitudes otimistas.'),
(110, 'v5.0', 'Mentalidade', 5, 'Subdomínio 4', 4, 'Tenho disciplina para manter minhas decisões.'),
(111, 'v5.0', 'Mentalidade', 5, 'Subdomínio 4', 4, 'Visualizo resultados antes de agir.'),
(112, 'v5.0', 'Mentalidade', 5, 'Subdomínio 4', 4, 'Mantenho uma postura proativa.'),
(113, 'v5.0', 'Mentalidade', 5, 'Subdomínio 5', 5, 'Procuro influenciar positivamente meu ambiente.'),
(114, 'v5.0', 'Mentalidade', 5, 'Subdomínio 5', 5, 'Acredito que minhas escolhas moldam meu futuro.'),
(115, 'v5.0', 'Mentalidade', 5, 'Subdomínio 5', 5, 'Reavalio minhas crenças quando necessário.'),
(116, 'v5.0', 'Mentalidade', 5, 'Subdomínio 5', 5, 'Estou comprometido com meu desenvolvimento.'),
(117, 'v5.0', 'Mentalidade', 5, 'Subdomínio 6', 6, 'Transformo intenção em ação.'),
(118, 'v5.0', 'Mentalidade', 5, 'Subdomínio 6', 6, 'Celebro pequenas conquistas.'),
(119, 'v5.0', 'Mentalidade', 5, 'Subdomínio 6', 6, 'Mantenho constância em meus objetivos.'),
(120, 'v5.0', 'Mentalidade', 5, 'Subdomínio 6', 6, 'Busco excelência em minhas atividades.'),
(121, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 1', 1, 'Consigo manter minhas decisões mesmo diante de dificuldades.'),
(122, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 1', 1, 'Assumo responsabilidade pelas minhas escolhas.'),
(123, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 1', 1, 'Penso antes de agir em situações importantes.'),
(124, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 1', 1, 'Mantenho o foco nos meus objetivos.'),
(125, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 2', 2, 'Escolho conscientemente minhas prioridades.'),
(126, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 2', 2, 'Evito agir apenas por impulso.'),
(127, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 2', 2, 'Persisto mesmo quando enfrento obstáculos.'),
(128, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 2', 2, 'Tenho disciplina para cumprir compromissos.'),
(129, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 3', 3, 'Avalio alternativas antes de decidir.'),
(130, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 3', 3, 'Aprendo com as consequências das minhas decisões.'),
(131, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 3', 3, 'Tenho autonomia para fazer escolhas alinhadas aos meus valores.'),
(132, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 3', 3, 'Resisto a pressões que desviam meus objetivos.'),
(133, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 4', 4, 'Reflito antes de mudar de direção.'),
(134, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 4', 4, 'Administro bem conflitos internos ao decidir.'),
(135, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 4', 4, 'Mantenho coerência entre decisão e ação.'),
(136, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 4', 4, 'Busco decisões baseadas em princípios.'),
(137, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 5', 5, 'Tenho clareza sobre o que depende de mim.'),
(138, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 5', 5, 'Assumo os resultados das minhas escolhas.'),
(139, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 5', 5, 'Sei dizer não quando necessário.'),
(140, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 5', 5, 'Priorizo o que é realmente importante.'),
(141, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 6', 6, 'Minhas decisões favorecem meu crescimento.'),
(142, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 6', 6, 'Planejo antes de executar.'),
(143, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 6', 6, 'Tenho constância na execução das decisões.'),
(144, 'v5.0', 'Liberdade Deliberativa', 6, 'Subdomínio 6', 6, 'Transformo decisões em ações concretas.'),
(145, 'v5.0', 'Inteligência Emocional', 7, 'Autoconsciência Emocional', 1, 'Reconheço minhas emoções assim que surgem.'),
(146, 'v5.0', 'Inteligência Emocional', 7, 'Autoconsciência Emocional', 1, 'Identifico a causa das minhas emoções.'),
(147, 'v5.0', 'Inteligência Emocional', 7, 'Autoconsciência Emocional', 1, 'Consigo expressar emoções de forma saudável.'),
(148, 'v5.0', 'Inteligência Emocional', 7, 'Autoconsciência Emocional', 1, 'Percebo como minhas emoções influenciam minhas decisões.'),
(149, 'v5.0', 'Inteligência Emocional', 7, 'Autorregulação', 2, 'Mantenho o autocontrole em situações difíceis.'),
(150, 'v5.0', 'Inteligência Emocional', 7, 'Autorregulação', 2, 'Lido bem com frustrações.'),
(151, 'v5.0', 'Inteligência Emocional', 7, 'Autorregulação', 2, 'Recupero-me rapidamente após adversidades.'),
(152, 'v5.0', 'Inteligência Emocional', 7, 'Autorregulação', 2, 'Evito agir impulsivamente.'),
(153, 'v5.0', 'Inteligência Emocional', 7, 'Empatia', 3, 'Demonstro empatia pelas pessoas.'),
(154, 'v5.0', 'Inteligência Emocional', 7, 'Empatia', 3, 'Procuro compreender diferentes perspectivas.'),
(155, 'v5.0', 'Inteligência Emocional', 7, 'Empatia', 3, 'Escuto atentamente antes de responder.'),
(156, 'v5.0', 'Inteligência Emocional', 7, 'Empatia', 3, 'Respeito as emoções dos outros.'),
(157, 'v5.0', 'Inteligência Emocional', 7, 'Gestão Emocional', 4, 'Consigo resolver conflitos de forma construtiva.'),
(158, 'v5.0', 'Inteligência Emocional', 7, 'Gestão Emocional', 4, 'Administro o estresse de forma saudável.'),
(159, 'v5.0', 'Inteligência Emocional', 7, 'Gestão Emocional', 4, 'Peço ajuda quando necessário.'),
(160, 'v5.0', 'Inteligência Emocional', 7, 'Gestão Emocional', 4, 'Aprendo com experiências emocionais.'),
(161, 'v5.0', 'Inteligência Emocional', 7, 'Relacionamentos', 5, 'Uso minhas emoções para fortalecer relacionamentos.'),
(162, 'v5.0', 'Inteligência Emocional', 7, 'Relacionamentos', 5, 'Transformo emoções negativas em aprendizado.'),
(163, 'v5.0', 'Inteligência Emocional', 7, 'Relacionamentos', 5, 'Mantenho equilíbrio emocional sob pressão.'),
(164, 'v5.0', 'Inteligência Emocional', 7, 'Relacionamentos', 5, 'Cultivo atitudes positivas.'),
(165, 'v5.0', 'Inteligência Emocional', 7, 'Desenvolvimento Emocional', 6, 'Reconheço o impacto emocional das minhas ações.'),
(166, 'v5.0', 'Inteligência Emocional', 7, 'Desenvolvimento Emocional', 6, 'Promovo ambientes emocionalmente saudáveis.'),
(167, 'v5.0', 'Inteligência Emocional', 7, 'Desenvolvimento Emocional', 6, 'Desenvolvo continuamente minha inteligência emocional.'),
(168, 'v5.0', 'Inteligência Emocional', 7, 'Desenvolvimento Emocional', 6, 'Minhas emoções fortalecem meu propósito.'),
(169, 'v5.0', 'Hábitos', 8, 'Subdomínio 1', 1, 'Cumpro os compromissos que assumo.'),
(170, 'v5.0', 'Hábitos', 8, 'Subdomínio 1', 1, 'Mantenho uma rotina diária organizada.'),
(171, 'v5.0', 'Hábitos', 8, 'Subdomínio 1', 1, 'Concluo tarefas iniciadas.'),
(172, 'v5.0', 'Hábitos', 8, 'Subdomínio 1', 1, 'Administro bem meu tempo.'),
(173, 'v5.0', 'Hábitos', 8, 'Subdomínio 2', 2, 'Meus hábitos apoiam meus objetivos.'),
(174, 'v5.0', 'Hábitos', 8, 'Subdomínio 2', 2, 'Tenho disciplina mesmo sem motivação.'),
(175, 'v5.0', 'Hábitos', 8, 'Subdomínio 2', 2, 'Persisto diante das dificuldades.'),
(176, 'v5.0', 'Hábitos', 8, 'Subdomínio 2', 2, 'Reviso minha rotina periodicamente.'),
(177, 'v5.0', 'Hábitos', 8, 'Subdomínio 3', 3, 'Cuido regularmente da minha saúde.'),
(178, 'v5.0', 'Hábitos', 8, 'Subdomínio 3', 3, 'Durmo o suficiente para manter meu desempenho.'),
(179, 'v5.0', 'Hábitos', 8, 'Subdomínio 3', 3, 'Pratico atividade física com frequência.'),
(180, 'v5.0', 'Hábitos', 8, 'Subdomínio 3', 3, 'Tenho alimentação compatível com meus objetivos.'),
(181, 'v5.0', 'Hábitos', 8, 'Subdomínio 4', 4, 'Evito hábitos que prejudicam meu desenvolvimento.'),
(182, 'v5.0', 'Hábitos', 8, 'Subdomínio 4', 4, 'Substituo hábitos negativos por positivos.'),
(183, 'v5.0', 'Hábitos', 8, 'Subdomínio 4', 4, 'Mantenho constância nas ações importantes.'),
(184, 'v5.0', 'Hábitos', 8, 'Subdomínio 4', 4, 'Reconheço quando preciso ajustar minha rotina.'),
(185, 'v5.0', 'Hábitos', 8, 'Subdomínio 5', 5, 'Planejo minha semana com antecedência.'),
(186, 'v5.0', 'Hábitos', 8, 'Subdomínio 5', 5, 'Acompanho meu progresso.'),
(187, 'v5.0', 'Hábitos', 8, 'Subdomínio 5', 5, 'Celebro pequenas conquistas.'),
(188, 'v5.0', 'Hábitos', 8, 'Subdomínio 5', 5, 'Aprendo com recaídas.'),
(189, 'v5.0', 'Hábitos', 8, 'Subdomínio 6', 6, 'Tenho hábitos alinhados ao meu propósito.'),
(190, 'v5.0', 'Hábitos', 8, 'Subdomínio 6', 6, 'Minhas rotinas refletem meus valores.'),
(191, 'v5.0', 'Hábitos', 8, 'Subdomínio 6', 6, 'Busco melhoria contínua.'),
(192, 'v5.0', 'Hábitos', 8, 'Subdomínio 6', 6, 'Meus hábitos favorecem resultados sustentáveis.'),
(193, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 1', 1, 'Comunico minhas ideias com clareza.'),
(194, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 1', 1, 'Escuto atentamente antes de responder.'),
(195, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 1', 1, 'Demonstro interesse genuíno pelas pessoas.'),
(196, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 1', 1, 'Consigo adaptar minha comunicação ao contexto.'),
(197, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 2', 2, 'Expresso minhas emoções de forma respeitosa.'),
(198, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 2', 2, 'Lido bem com conversas difíceis.'),
(199, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 2', 2, 'Respeito opiniões diferentes das minhas.'),
(200, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 2', 2, 'Busco resolver conflitos de forma construtiva.'),
(201, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 3', 3, 'Faço perguntas para compreender melhor.'),
(202, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 3', 3, 'Evito julgamentos precipitados.'),
(203, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 3', 3, 'Dou feedback de forma útil.'),
(204, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 3', 3, 'Recebo feedback com abertura.'),
(205, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 4', 4, 'Construo relacionamentos de confiança.'),
(206, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 4', 4, 'Cumpro compromissos assumidos.'),
(207, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 4', 4, 'Coopero com outras pessoas.'),
(208, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 4', 4, 'Valorizo o trabalho em equipe.'),
(209, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 5', 5, 'Percebo sinais não verbais na comunicação.'),
(210, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 5', 5, 'Sou empático ao conversar.'),
(211, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 5', 5, 'Consigo negociar soluções equilibradas.'),
(212, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 5', 5, 'Mantenho o autocontrole durante discussões.'),
(213, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 6', 6, 'Minhas relações fortalecem meus objetivos.'),
(214, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 6', 6, 'Invisto tempo em relacionamentos importantes.'),
(215, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 6', 6, 'Comunico expectativas claramente.'),
(216, 'v5.0', 'Comunicação e Relacionamentos', 9, 'Subdomínio 6', 6, 'Promovo um ambiente de respeito.'),
(217, 'v5.0', 'Liderança e Influência', 10, 'Autoliderança', 1, 'Assumo responsabilidade pelas minhas decisões.'),
(218, 'v5.0', 'Liderança e Influência', 10, 'Autoliderança', 1, 'Mantenho disciplina diante dos desafios.'),
(219, 'v5.0', 'Liderança e Influência', 10, 'Autoliderança', 1, 'Inspiro confiança nas pessoas.'),
(220, 'v5.0', 'Liderança e Influência', 10, 'Autoliderança', 1, 'Influencio positivamente meu ambiente.'),
(221, 'v5.0', 'Liderança e Influência', 10, 'Influência', 2, 'Comunico uma visão clara.'),
(222, 'v5.0', 'Liderança e Influência', 10, 'Influência', 2, 'Motivo pessoas pelo exemplo.'),
(223, 'v5.0', 'Liderança e Influência', 10, 'Influência', 2, 'Tomo decisões mesmo em cenários difíceis.'),
(224, 'v5.0', 'Liderança e Influência', 10, 'Influência', 2, 'Analiso riscos antes de decidir.'),
(225, 'v5.0', 'Liderança e Influência', 10, 'Tomada de Decisão', 3, 'Assumo responsabilidade pelos resultados.'),
(226, 'v5.0', 'Liderança e Influência', 10, 'Tomada de Decisão', 3, 'Aprendo com decisões equivocadas.'),
(227, 'v5.0', 'Liderança e Influência', 10, 'Tomada de Decisão', 3, 'Delego tarefas adequadamente.'),
(228, 'v5.0', 'Liderança e Influência', 10, 'Tomada de Decisão', 3, 'Confio nas pessoas da equipe.'),
(229, 'v5.0', 'Liderança e Influência', 10, 'Delegação', 4, 'Desenvolvo o potencial de outras pessoas.'),
(230, 'v5.0', 'Liderança e Influência', 10, 'Delegação', 4, 'Ofereço feedback construtivo.'),
(231, 'v5.0', 'Liderança e Influência', 10, 'Delegação', 4, 'Reconheço conquistas da equipe.'),
(232, 'v5.0', 'Liderança e Influência', 10, 'Delegação', 4, 'Promovo colaboração.'),
(233, 'v5.0', 'Liderança e Influência', 10, 'Desenvolvimento de Pessoas', 5, 'Sirvo antes de ser servido.'),
(234, 'v5.0', 'Liderança e Influência', 10, 'Desenvolvimento de Pessoas', 5, 'Exerço liderança com humildade.'),
(235, 'v5.0', 'Liderança e Influência', 10, 'Desenvolvimento de Pessoas', 5, 'Busco o bem coletivo.'),
(236, 'v5.0', 'Liderança e Influência', 10, 'Desenvolvimento de Pessoas', 5, 'Lidero com princípios.'),
(237, 'v5.0', 'Liderança e Influência', 10, 'Liderança Servidora', 6, 'Minha liderança gera crescimento.'),
(238, 'v5.0', 'Liderança e Influência', 10, 'Liderança Servidora', 6, 'As pessoas se sentem respeitadas ao trabalhar comigo.'),
(239, 'v5.0', 'Liderança e Influência', 10, 'Liderança Servidora', 6, 'Procuro desenvolver sucessores.'),
(240, 'v5.0', 'Liderança e Influência', 10, 'Liderança Servidora', 6, 'Minha influência permanece mesmo sem autoridade formal.'),
(241, 'v5.0', 'Propósito e Realização', 11, 'Propósito', 1, 'Tenho clareza sobre meu propósito de vida.'),
(242, 'v5.0', 'Propósito e Realização', 11, 'Propósito', 1, 'Meu propósito orienta minhas decisões.'),
(243, 'v5.0', 'Propósito e Realização', 11, 'Propósito', 1, 'Minhas metas refletem meus valores.'),
(244, 'v5.0', 'Propósito e Realização', 11, 'Propósito', 1, 'Sinto que minha vida possui direção.'),
(245, 'v5.0', 'Propósito e Realização', 11, 'Metas', 2, 'Meus objetivos são específicos.'),
(246, 'v5.0', 'Propósito e Realização', 11, 'Metas', 2, 'Planejo minhas ações para alcançar meus objetivos.'),
(247, 'v5.0', 'Propósito e Realização', 11, 'Metas', 2, 'Acompanho meu progresso regularmente.'),
(248, 'v5.0', 'Propósito e Realização', 11, 'Metas', 2, 'Reavalio metas quando necessário.'),
(249, 'v5.0', 'Propósito e Realização', 11, 'Execução', 3, 'Persisto diante das dificuldades.'),
(250, 'v5.0', 'Propósito e Realização', 11, 'Execução', 3, 'Mantenho o foco no longo prazo.'),
(251, 'v5.0', 'Propósito e Realização', 11, 'Execução', 3, 'Concluo o que começo.'),
(252, 'v5.0', 'Propósito e Realização', 11, 'Execução', 3, 'Transformo planos em ações.'),
(253, 'v5.0', 'Propósito e Realização', 11, 'Significado', 4, 'Minhas atividades geram significado.'),
(254, 'v5.0', 'Propósito e Realização', 11, 'Significado', 4, 'Percebo impacto positivo do meu trabalho.'),
(255, 'v5.0', 'Propósito e Realização', 11, 'Significado', 4, 'Busco excelência no que faço.'),
(256, 'v5.0', 'Propósito e Realização', 11, 'Significado', 4, 'Celebro conquistas de forma equilibrada.'),
(257, 'v5.0', 'Propósito e Realização', 11, 'Melhoria Contínua', 5, 'Aprendo com os resultados obtidos.'),
(258, 'v5.0', 'Propósito e Realização', 11, 'Melhoria Contínua', 5, 'Uso erros como oportunidade de crescimento.'),
(259, 'v5.0', 'Propósito e Realização', 11, 'Melhoria Contínua', 5, 'Busco melhoria contínua.'),
(260, 'v5.0', 'Propósito e Realização', 11, 'Melhoria Contínua', 5, 'Invisto no meu desenvolvimento.'),
(261, 'v5.0', 'Propósito e Realização', 11, 'Legado', 6, 'Minhas realizações contribuem para outras pessoas.'),
(262, 'v5.0', 'Propósito e Realização', 11, 'Legado', 6, 'Alinho sucesso com serviço.'),
(263, 'v5.0', 'Propósito e Realização', 11, 'Legado', 6, 'Minha realização fortalece meu propósito.'),
(264, 'v5.0', 'Propósito e Realização', 11, 'Legado', 6, 'Tenho visão de legado.'),
(265, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Espiritualidade Pessoal', 1, 'Minha espiritualidade influencia minhas decisões diárias.'),
(266, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Espiritualidade Pessoal', 1, 'Reservo tempo para fortalecer minha vida espiritual.'),
(267, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Espiritualidade Pessoal', 1, 'Procuro viver de acordo com meus princípios espirituais.'),
(268, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Espiritualidade Pessoal', 1, 'Minha fé fortalece minhas escolhas.'),
(269, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Princípios e Valores', 2, 'Tenho clareza dos valores que orientam minha vida.'),
(270, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Princípios e Valores', 2, 'Permaneço fiel aos meus princípios mesmo sob pressão.'),
(271, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Princípios e Valores', 2, 'Busco agir com integridade.'),
(272, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Princípios e Valores', 2, 'Meus valores orientam meu comportamento.'),
(273, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Relacionamento com Deus', 3, 'Sinto-me próximo de Deus em minha vida diária.'),
(274, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Relacionamento com Deus', 3, 'Procuro desenvolver meu relacionamento com Deus.'),
(275, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Relacionamento com Deus', 3, 'Busco orientação espiritual antes de decisões importantes.'),
(276, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Relacionamento com Deus', 3, 'Reconheço a influência de Deus em minha vida.'),
(277, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Propósito Espiritual', 4, 'Entendo como meu propósito espiritual orienta minha missão.'),
(278, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Propósito Espiritual', 4, 'Procuro viver com significado eterno.'),
(279, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Propósito Espiritual', 4, 'Minha espiritualidade fortalece meu senso de propósito.'),
(280, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Propósito Espiritual', 4, 'Alinho meus objetivos aos meus princípios.'),
(281, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Serviço', 5, 'Procuro servir outras pessoas voluntariamente.'),
(282, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Serviço', 5, 'Sinto satisfação em contribuir para o bem do próximo.'),
(283, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Serviço', 5, 'Uso meus talentos para beneficiar outras pessoas.'),
(284, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Serviço', 5, 'Sirvo com disposição e humildade.'),
(285, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Crescimento Espiritual', 6, 'Busco crescer espiritualmente continuamente.'),
(286, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Crescimento Espiritual', 6, 'Aprendo com minhas experiências espirituais.'),
(287, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Crescimento Espiritual', 6, 'Estou comprometido com meu desenvolvimento espiritual.'),
(288, 'v5.0', 'Desenvolvimento Espiritual', 12, 'Crescimento Espiritual', 6, 'Avalio regularmente meu progresso espiritual.')

on conflict (id, instrument_version) do update set
  domain_name = excluded.domain_name,
  domain_order = excluded.domain_order,
  subdomain_name = excluded.subdomain_name,
  subdomain_order = excluded.subdomain_order,
  question_text = excluded.question_text;