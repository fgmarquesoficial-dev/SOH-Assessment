/* ============================================================
   assessment.js
   Orquestra a gravação automática do assessment completo no
   Supabase, no momento em que o participante conclui a
   avaliação. Não interfere na renderização da interface —
   a gravação ocorre em segundo plano (fire-and-forget).
   ============================================================ */

async function persistAssessment(state, results) {
  try {
    const participant = await dbInsertParticipant(state.patient);

    const durationSeconds = state.startedAt
      ? Math.round((Date.now() - state.startedAt) / 1000)
      : null;

    const assessment = await dbInsertAssessment({
      participantId: participant.id,
      startedAt: state.startedAt || Date.now(),
      durationSeconds,
      results
    });

    await Promise.all([
      dbInsertAnswers(assessment.id, state.answers),
      dbInsertDomainScores(assessment.id, results.domainDetail),
      dbInsertSubdomainScores(assessment.id, results.domainDetail),
      dbInsertResults(assessment.id, results),
      dbInsertRecommendations(assessment.id, results)
    ]);

    state.savedAssessmentId = assessment.id;
    state.savedParticipantId = participant.id;
    console.info("[SOH] Avaliação salva com sucesso no Supabase. assessment_id:", assessment.id);
  } catch (err) {
    // Falha na gravação não deve interromper a experiência do participante/facilitador.
    // O relatório continua sendo exibido normalmente a partir dos dados locais.
    console.error("[SOH] Falha ao salvar avaliação no Supabase:", err.message || err);
  }
}
