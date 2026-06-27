/// The Dream Team role roster — the 12 user-assignable agent roles, their display labels, their
/// stage grouping, and which roles fall back to the DEEP tier. A **hand-mirror** of the engine's
/// `tradingagents/graph/agent_roles.py` (`ROLE_TO_NODE` / `DEEP_ROLES`), shared by Model Studio (the
/// per-role pickers) and the Hub (the post-run cast list) so the two surfaces can never drift from
/// each other. Pure Dart, no Flutter imports.
///
/// source of truth: tradingagents/graph/agent_roles.py (ROLE_TO_NODE keys + labels, DEEP_ROLES).
/// Keep in sync — `dream_team_roster_test.dart` guards the keys/labels/tiers; a Python
/// roster-integrity test guards the node-name side. The /catalog endpoint does NOT (yet) serve the
/// roster, so this mirror is the single Dart source. Do NOT reuse the `AgentId` enum (events.dart):
/// its wire keys differ (`market`/`bull`/`portfolio` vs `market_analyst`/`bull_researcher`/
/// `portfolio_manager`) — using them as role keys would silently no-op every override engine-side.
library;

/// The 12 wire role keys, in engine pipeline order. These are the exact keys the engine's
/// `ROLE_TO_NODE` is keyed by and the keys carried on the `agent_models` wire map.
const List<String> dreamTeamRoleKeys = [
  'market_analyst',
  'social_analyst',
  'news_analyst',
  'fundamentals_analyst',
  'bull_researcher',
  'bear_researcher',
  'research_manager',
  'trader',
  'aggressive_analyst',
  'neutral_analyst',
  'conservative_analyst',
  'portfolio_manager',
];

/// role key -> display label (verbatim from `ROLE_TO_NODE` values — note `social_analyst` labels as
/// "Sentiment Analyst", the easy-to-get-wrong one).
const Map<String, String> dreamTeamRoleLabels = {
  'market_analyst': 'Market Analyst',
  'social_analyst': 'Sentiment Analyst',
  'news_analyst': 'News Analyst',
  'fundamentals_analyst': 'Fundamentals Analyst',
  'bull_researcher': 'Bull Researcher',
  'bear_researcher': 'Bear Researcher',
  'research_manager': 'Research Manager',
  'trader': 'Trader',
  'aggressive_analyst': 'Aggressive Analyst',
  'neutral_analyst': 'Neutral Analyst',
  'conservative_analyst': 'Conservative Analyst',
  'portfolio_manager': 'Portfolio Manager',
};

/// The two judge roles that default to the engine's DEEP client; every other role defaults to QUICK.
/// Mirrors `agent_roles.DEEP_ROLES`. Drives the "Falls back · DEEP/QUICK" chip on unassigned roles.
const Set<String> dreamTeamDeepRoles = {'research_manager', 'portfolio_manager'};

/// The roster grouped into 5 stages, in pipeline order (analysts → research debate → trader → risk
/// team → portfolio), matching the order the engine runs them and the terminal pipeline rail. Each
/// entry is `(stageLabel, orderedRoleKeys)`.
const List<(String, List<String>)> dreamTeamStages = [
  ('Analyst desks', ['market_analyst', 'social_analyst', 'news_analyst', 'fundamentals_analyst']),
  ('Research debate', ['bull_researcher', 'bear_researcher', 'research_manager']),
  ('Trader', ['trader']),
  ('Risk team', ['aggressive_analyst', 'neutral_analyst', 'conservative_analyst']),
  ('Portfolio', ['portfolio_manager']),
];

/// Display label for a role key (falls back to the raw key if somehow unknown).
String dreamTeamRoleLabel(String roleKey) => dreamTeamRoleLabels[roleKey] ?? roleKey;

/// Whether an *unassigned* role falls back to the DEEP tier (the two judges) vs QUICK (everyone else).
bool roleFallsBackToDeep(String roleKey) => dreamTeamDeepRoles.contains(roleKey);
