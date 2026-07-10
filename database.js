/* ============================================================
   database.js
   Camada de acesso a dados — todas as escritas no Supabase
   passam por este módulo. Nenhuma outra parte do sistema
   monta queries diretamente.

   Arquitetura (v3):
     participants        → cadastro do participante
     questions            → banco oficial das 288 questões (referência)
     assessments          → uma aplicação completa do instrumento
     answers               → 288 respostas, cada uma referenciando questions
     domain_scores         → pontuação dos 12 domínios
     subdomain_scores       → pontuação dos 72 subdomínios
     results                → radar, macrodimensões, interpretações
     recommendations         → plano de ação (PEDI™), 1 linha por domínio
   ============================================================ */

async function dbInsertParticipant(patient) {
  const sb = initSupabase();
  if (!sb) throw new Error("Cliente Supabase não inicializado.");

  const id = crypto.randomUUID();

  const { error } = await sb
    .from("participants")
    .insert({
      id,
      assessment_date: patient.data || null,
      assessment_time: new Date().toTimeString().slice(0, 8),
      nome: patient.nome,
      email: patient.email || null,
      telefone: patient.telefone || null,
      empresa: patient.empresa || null,
      cargo: patient.profissao || null,
      cidade: patient.cidade || null,
      estado: patient.estado || null,
      sexo: patient.sexo || null,
      idade: patient.idade ? parseInt(patient.idade, 10) : null,
      estado_civil: patient.estadoCivil || null,
      escolaridade: patient.escolaridade || null,
      facilitador: patient.facilitador || null,
      programa: patient.programa || null,
      observacoes: patient.observacoes || null
    });

  if (error) throw error;
  return { id };
}

async function dbInsertAssessment({ participantId, startedAt, durationSeconds, results }) {
  const sb = initSupabase();
  if (!sb) throw new Error("Cliente Supabase não inicializado.");

  const id = crypto.randomUUID();
  const igsohClass = classify(results.IGSOH).label;

  const { error } = await sb
    .from("assessments")
    .insert({
      id,
      participant_id: participantId,
      instrument_version: INSTRUMENT_VERSION,
      started_at: new Date(startedAt).toISOString(),
      duration_seconds: Number.isFinite(durationSeconds) ? durationSeconds : null,
      igsoh: results.IGSOH,
      igsoh_classification: igsohClass,
      ics: results.ICS,
      itp: results.ITP,
      ire: results.IRE,
      iei: results.IEI,
      cpt_domain: results.cpt.domain,
      cpt_score: round2(results.cpt.score),
      status: "completed"
    });

  if (error) throw error;
  return { id };
}

async function dbInsertAnswers(assessmentId, answers) {
  const sb = initSupabase();
  const rows = QUESTIONS.map(q => ({
    assessment_id: assessmentId,
    question_id: q.n,
    instrument_version: INSTRUMENT_VERSION,
    answer_value: answers[q.n]
  }));
  // Insere em lotes de 100 para evitar payloads muito grandes
  for (let i = 0; i < rows.length; i += 100) {
    const batch = rows.slice(i, i + 100);
    const { error } = await sb.from("answers").insert(batch);
    if (error) throw error;
  }
}

async function dbInsertDomainScores(assessmentId, domainDetail) {
  const sb = initSupabase();
  const rows = DOMAIN_ORDER.map((domainName, i) => ({
    assessment_id: assessmentId,
    domain_name: domainName,
    domain_order: i + 1,
    score: domainDetail[domainName].score,
    classification: classify(domainDetail[domainName].score).label
  }));
  const { error } = await sb.from("domain_scores").insert(rows);
  if (error) throw error;
}

async function dbInsertSubdomainScores(assessmentId, domainDetail) {
  const sb = initSupabase();
  const rows = [];
  DOMAIN_ORDER.forEach(domainName => {
    domainDetail[domainName].subdomains.forEach((sub, i) => {
      rows.push({
        assessment_id: assessmentId,
        domain_name: domainName,
        subdomain_name: sub.name,
        subdomain_order: i + 1,
        score: sub.score
      });
    });
  });
  const { error } = await sb.from("subdomain_scores").insert(rows);
  if (error) throw error;
}

async function dbInsertResults(assessmentId, results) {
  const sb = initSupabase();

  const interpretations = {
    IGSOH: "Índice Geral do Sistema Operacional Humano™ — média dos 12 domínios. Representa o nível global de desenvolvimento.",
    ICS: "Consistência do Sistema — mede o equilíbrio entre os domínios (quanto mais próximo de 5, mais uniforme o desenvolvimento).",
    ITP: "Transformação Potencial — capacidade de mudança nos domínios de base cognitiva e autorregulatória.",
    IRE: "Realização Estratégica — capacidade de converter potencial em resultado prático.",
    IEI: "Equilíbrio Integral — equilíbrio entre as 4 macrodimensões do sistema."
  };

  const { error } = await sb.from("results").insert({
    assessment_id: assessmentId,
    radar_data: DOMAIN_ORDER.map((d, i) => ({ domain: d, score: round2(results.domainScoreList[i]) })),
    macrodimensions: MACRODIMENSIONS.map(m => ({ name: m.name, score: round2(results.macroScores[m.name]) })),
    interpretations,
    pontos_fortes: results.pontosFortes.map(p => ({ domain: p.domain, score: round2(p.score) })),
    pontos_vulneraveis: results.pontosVulneraveis.map(p => ({ domain: p.domain, score: round2(p.score) }))
  });

  if (error) throw error;
}

async function dbInsertRecommendations(assessmentId, results) {
  const sb = initSupabase();
  const rows = results.pedi.map(item => ({
    assessment_id: assessmentId,
    prioridade: item.priority,
    domain_name: item.domain,
    score: item.score,
    classification: item.classification,
    protocolo: item.protocol,
    nivel: item.priority === 1 ? "1 - Obrigatório" : (item.priority <= 3 ? "2 - Complementar" : "3 - Manutenção"),
    prazo: item.prazo,
    status: null
  }));
  const { error } = await sb.from("recommendations").insert(rows);
  if (error) throw error;
}

/* ------------------------------------------------------------
   Consulta de verificação (uso opcional, ex.: painel futuro)
   ------------------------------------------------------------ */
async function dbGetAssessmentSummary(assessmentId) {
  const sb = initSupabase();
  const { data, error } = await sb
    .from("assessments")
    .select("*, participants(nome, email, cidade, estado), domain_scores(*), results(*), recommendations(*)")
    .eq("id", assessmentId)
    .single();
  if (error) throw error;
  return data;
}
