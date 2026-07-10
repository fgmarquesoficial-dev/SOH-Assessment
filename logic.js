/* ===================== CONFIGURAÇÃO DO INSTRUMENTO ===================== */

const INSTRUMENT_VERSION = "v5.0";

const MACRODIMENSIONS = [
  { name: "Arquitetura Cognitiva™", domains: ["Identidade", "Paradigmas", "Programação Mental"] },
  { name: "Arquitetura Autorregulatória™", domains: ["Consciência", "Mentalidade", "Liberdade Deliberativa"] },
  { name: "Arquitetura Comportamental™", domains: ["Inteligência Emocional", "Hábitos", "Comunicação e Relacionamentos"] },
  { name: "Arquitetura de Realização™", domains: ["Liderança e Influência", "Propósito e Realização", "Desenvolvimento Espiritual"] }
];

const ITP_DOMAINS = ["Paradigmas", "Programação Mental", "Consciência", "Mentalidade", "Liberdade Deliberativa"];
const IRE_DOMAINS = ["Mentalidade", "Hábitos", "Liderança e Influência", "Propósito e Realização", "Comunicação e Relacionamentos"];

const PROTOCOLS = {
  "Identidade": "Reconstrução da Identidade™",
  "Paradigmas": "Reconstrução de Paradigmas™",
  "Programação Mental": "Programação Mental™",
  "Consciência": "Consciência Plena™",
  "Mentalidade": "Mentalidade da Excelência™",
  "Liberdade Deliberativa": "Liberdade Deliberativa™",
  "Inteligência Emocional": "Inteligência Emocional™",
  "Hábitos": "Formação de Hábitos™",
  "Comunicação e Relacionamentos": "Comunicação Consciente™",
  "Liderança e Influência": "Liderança Servidora™",
  "Propósito e Realização": "Definição de Propósito™",
  "Desenvolvimento Espiritual": "Desenvolvimento Espiritual™"
};

const CLASSIFICATION_BANDS = [
  { min: 1.00, max: 1.79, label: "Desenvolvimento Crítico", css: "class-critico", color: "#8E3B37" },
  { min: 1.80, max: 2.59, label: "Desenvolvimento Inicial", css: "class-inicial", color: "#A2472C" },
  { min: 2.60, max: 3.39, label: "Desenvolvimento Moderado", css: "class-moderado", color: "#B08A2E" },
  { min: 3.40, max: 4.19, label: "Desenvolvimento Consistente", css: "class-consistente", color: "#33574B" },
  { min: 4.20, max: 5.001, label: "Desenvolvimento de Excelência", css: "class-excelencia", color: "#203C33" }
];

const LIKERT_LABELS = ["Nunca ou\nquase nunca", "Raramente", "Às vezes", "Frequentemente", "Sempre ou\nquase sempre"];

function classify(score) {
  for (const b of CLASSIFICATION_BANDS) {
    if (score >= b.min && score <= b.max) return b;
  }
  return CLASSIFICATION_BANDS[0];
}

function round2(n) { return Math.round(n * 100) / 100; }

function mean(arr) { return arr.reduce((a, b) => a + b, 0) / arr.length; }

function popStdev(arr) {
  const m = mean(arr);
  const variance = mean(arr.map(x => (x - m) * (x - m)));
  return Math.sqrt(variance);
}

/* ===================== MOTOR DE CÁLCULO ===================== */
// answers: { [questionNumber]: 1-5 }
function computeResults(answers) {
  const domainScores = {};
  const domainDetail = {};

  DOMAIN_ORDER.forEach(domName => {
    const domInfo = DOMAIN_MAP[domName];
    const subScores = [];
    const subDetail = [];
    domInfo.subs.forEach(sub => {
      const vals = sub.items.map(n => answers[n]);
      const avg = mean(vals);
      subScores.push(avg);
      subDetail.push({ name: sub.name, score: round2(avg), items: sub.items.map(n => ({ n, v: answers[n] })) });
    });
    const domAvg = mean(subScores);
    domainScores[domName] = domAvg;
    domainDetail[domName] = { score: round2(domAvg), subdomains: subDetail };
  });

  const domainScoreList = DOMAIN_ORDER.map(d => domainScores[d]);
  const IGSOH = mean(domainScoreList);

  const macroScores = {};
  MACRODIMENSIONS.forEach(m => {
    macroScores[m.name] = mean(m.domains.map(d => domainScores[d]));
  });
  const macroScoreList = MACRODIMENSIONS.map(m => macroScores[m.name]);

  const ICS = Math.min(5, Math.max(1, 5 - popStdev(domainScoreList)));
  const ITP = mean(ITP_DOMAINS.map(d => domainScores[d]));
  const IRE = mean(IRE_DOMAINS.map(d => domainScores[d]));
  const IEI = Math.min(5, Math.max(1, 5 - popStdev(macroScoreList)));

  // ranking for CPT / pontos fortes-vulneráveis
  const ranked = DOMAIN_ORDER.map(d => ({ domain: d, score: domainScores[d] })).sort((a, b) => a.score - b.score);
  const cpt = ranked[0];
  const nextPriority = ranked.slice(1, 3); // nível 2
  const strongest = ranked[ranked.length - 1];

  const pontosFortes = ranked.filter(r => classify(r.score).label.match(/Consistente|Excelência/)).slice(-3).reverse();
  const pontosVulneraveis = ranked.filter(r => classify(r.score).label.match(/Crítico|Inicial/)).slice(0, 3);

  const pedi = ranked.map((r, i) => ({
    priority: i + 1,
    domain: r.domain,
    score: round2(r.score),
    classification: classify(r.score).label,
    protocol: PROTOCOLS[r.domain],
    prazo: i < 3 ? "30 dias" : (i < 6 ? "90 dias" : "180 dias")
  }));

  return {
    domainScores, domainDetail,
    domainScoreList,
    IGSOH: round2(IGSOH),
    macroScores, macroScoreList,
    ICS: round2(ICS), ITP: round2(ITP), IRE: round2(IRE), IEI: round2(IEI),
    ranked, cpt, nextPriority, strongest,
    pontosFortes, pontosVulneraveis,
    pedi
  };
}
