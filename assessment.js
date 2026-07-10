/* ============================================================
   assessment.js
   Orquestra a gravação automática do assessment completo no
   Supabase, no momento em que o participante conclui a
   avaliação. Não interfere na renderização da interface —
   a gravação ocorre em segundo plano (fire-and-forget).
   ============================================================ */

function logSupabaseError(step, err) {
  // Erros do PostgREST/Postgres trazem detalhes muito mais úteis do
  // que err.message sozinho (code, details, hint) — sempre logamos tudo.
  console.error(`[SOH] Falha ao salvar (${step}):`, {
    message: err && err.message,
    details: err && err.details,
    hint: err && err.hint,
    code: err && err.code,
    raw: err
  });
  window.SOH_lastError = { step, err };
}

async function persistAssessment(state, results) {
  let step = "init";
  try {
    step = "cliente Supabase";
    const sb = initSupabase();
    if (!sb) throw new Error("Cliente Supabase não inicializado (verifique config.js e se o SDK carregou).");

    step = "participants";
    const participant = await dbInsertParticipant(state.patient);

    const durationSeconds = state.startedAt
      ? Math.round((Date.now() - state.startedAt) / 1000)
      : null;

    step = "assessments";
    const assessment = await dbInsertAssessment({
      participantId: participant.id,
      startedAt: state.startedAt || Date.now(),
      durationSeconds,
      results
    });

    step = "answers/domain_scores/subdomain_scores/results/recommendations";
    await Promise.all([
      dbInsertAnswers(assessment.id, state.answers),
      dbInsertDomainScores(assessment.id, results.domainDetail),
      dbInsertSubdomainScores(assessment.id, results.domainDetail),
      dbInsertResults(assessment.id, results),
      dbInsertRecommendations(assessment.id, results)
    ]);

    state.savedAssessmentId = assessment.id;
    state.savedParticipantId = participant.id;
    console.info("[SOH] Avaliação salva com sucesso no Supabase. assessment_id:", assessment.id, "participant_id:", participant.id);
  } catch (err) {
    // Falha na gravação não deve interromper a experiência do participante/facilitador.
    // O relatório continua sendo exibido normalmente a partir dos dados locais.
    logSupabaseError(step, err);
  }
}

/* ------------------------------------------------------------
   Diagnóstico manual — rode SOH_testConnection() no console do
   navegador (F12) para confirmar rapidamente se a conexão com o
   Supabase está funcionando, sem precisar preencher todo o
   assessment.
   ------------------------------------------------------------ */
async function SOH_testConnection() {
  console.info("[SOH] Testando conexão com Supabase...");
  const sb = initSupabase();
  if (!sb) {
    console.error("[SOH] FALHOU: cliente não inicializado. Verifique se a tag <script> do CDN carregou (veja a aba Network) e se config.js tem a URL/chave corretas.");
    return false;
  }
  try {
    const { data, error } = await sb.from("questions").select("id").limit(1);
    if (error) {
      console.error("[SOH] FALHOU ao ler a tabela 'questions':", error);
      return false;
    }
    console.info("[SOH] Leitura OK. Exemplo:", data);

    const testId = crypto.randomUUID();
    const { error: insErr } = await sb.from("participants").insert({
      id: testId,
      nome: "__SOH_TESTE_CONEXAO__"
    });
    if (insErr) {
      console.error("[SOH] FALHOU ao inserir em 'participants' (provável causa: RLS/policy):", insErr);
      return false;
    }
    console.info("[SOH] Inserção de teste em 'participants' OK. id:", testId);
    console.info("[SOH] Tudo funcionando. Esse registro de teste pode ser apagado no Table Editor do Supabase.");
    return true;
  } catch (e) {
    console.error("[SOH] Erro inesperado no teste:", e);
    return false;
  }
}
