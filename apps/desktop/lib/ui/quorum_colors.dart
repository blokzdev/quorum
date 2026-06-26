import 'package:flutter/material.dart';
import 'package:quorum_core/quorum_core.dart';

/// Design-brief tokens (dark calm-luxury). The full ThemeExtension set + bundled fonts land in S4;
/// S3 uses these constants directly to nail the IA, layout, and colour semantics first.
class QC {
  QC._();
  // Brand type: Inter for UI, JetBrains Mono for numerics (bundled under apps/desktop/fonts/).
  static const fontUi = 'Inter';
  static const fontMono = 'JetBrainsMono';
  static const bg = Color(0xFF0A0C10);
  static const surface1 = Color(0xFF12151C);
  static const surface2 = Color(0xFF1A1E27);
  static const border = Color(0xFF2A313D);
  static const textHi = Color(0xFFE6EAF2);
  static const textMid = Color(0xFF9AA4B2);
  // Lifted from #5B6473 (~2.4:1, failed WCAG) to a readable-but-recessive grey for structural labels.
  static const textLo = Color(0xFF7C8694);
  static const accent = Color(0xFF3D7DFF);
  static const up = Color(0xFF26C281);
  static const down = Color(0xFFFF5C5C);
  static const warning = Color(0xFFFFB02E);
}

const _agentMeta = <AgentId, (String, Color)>{
  AgentId.market: ('Market Analyst', Color(0xFF58B6FF)),
  AgentId.social: ('Sentiment Analyst', Color(0xFFC58BFF)),
  AgentId.news: ('News Analyst', Color(0xFFFFB02E)),
  AgentId.fundamentals: ('Fundamentals Analyst', Color(0xFF4EC3A6)),
  AgentId.bull: ('Bull Researcher', Color(0xFF26C281)),
  AgentId.bear: ('Bear Researcher', Color(0xFFFF5C5C)),
  AgentId.researchManager: ('Research Manager', Color(0xFF3D7DFF)),
  AgentId.trader: ('Trader', Color(0xFF3D7DFF)),
  AgentId.aggressive: ('Aggressive Analyst', Color(0xFFFF8A3D)),
  AgentId.neutral: ('Neutral Analyst', Color(0xFF7C8AA5)),
  AgentId.conservative: ('Conservative Analyst', Color(0xFF4EC3A6)),
  AgentId.portfolio: ('Portfolio Manager', Color(0xFFFFD166)),
};

String agentName(AgentId a) => _agentMeta[a]?.$1 ?? a.name;
Color agentColor(AgentId a) => _agentMeta[a]?.$2 ?? QC.textMid;

/// The five phases in order, each with its display label and the agents it contains.
const stageMeta = <Stage, (String, List<AgentId>)>{
  Stage.analysts: ('Analysts', [AgentId.market, AgentId.social, AgentId.news, AgentId.fundamentals]),
  Stage.researchDebate: ('Research Debate', [AgentId.bull, AgentId.bear, AgentId.researchManager]),
  Stage.trader: ('Trader', [AgentId.trader]),
  Stage.riskDebate: ('Risk Debate', [AgentId.aggressive, AgentId.neutral, AgentId.conservative]),
  Stage.portfolio: ('Portfolio', [AgentId.portfolio]),
};

/// Which agent authored each report section (for attribution chips on the cards).
const sectionAgent = <String, AgentId>{
  'market_report': AgentId.market,
  'sentiment_report': AgentId.social,
  'news_report': AgentId.news,
  'fundamentals_report': AgentId.fundamentals,
  'bull': AgentId.bull,
  'bear': AgentId.bear,
  'investment_plan': AgentId.researchManager,
  'trader_investment_plan': AgentId.trader,
  'aggressive': AgentId.aggressive,
  'conservative': AgentId.conservative,
  'neutral': AgentId.neutral,
  'final_trade_decision': AgentId.portfolio,
};

const sectionTitle = <String, String>{
  'market_report': 'Market',
  'sentiment_report': 'Sentiment',
  'news_report': 'News',
  'fundamentals_report': 'Fundamentals',
  'bull': 'Bull Case',
  'bear': 'Bear Case',
  'investment_plan': 'Research Decision',
  'trader_investment_plan': 'Trade Plan',
  'aggressive': 'Aggressive View',
  'conservative': 'Conservative View',
  'neutral': 'Neutral View',
  'final_trade_decision': 'Portfolio Decision',
};

/// Colour for a BUY/HOLD/SELL-family rating.
Color ratingColor(String? rating) {
  switch (rating?.toLowerCase()) {
    case 'buy':
    case 'overweight':
      return QC.up;
    case 'sell':
    case 'underweight':
      return QC.down;
    default:
      return QC.warning; // hold / unknown
  }
}
