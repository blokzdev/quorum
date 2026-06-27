import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/dream_team_roster.dart';

/// Guards the hand-mirrored Dream Team roster against drift from the engine's
/// `tradingagents/graph/agent_roles.py` (ROLE_TO_NODE / DEEP_ROLES). A silent drift here would make
/// the roster golden pass against a stale list and ship overrides under keys the engine ignores.
void main() {
  group('Dream Team roster mirror', () {
    test('exactly the 12 frozen role keys, in pipeline order', () {
      expect(dreamTeamRoleKeys, const [
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
      ]);
    });

    test('every key has a label; social_analyst is "Sentiment Analyst"', () {
      for (final key in dreamTeamRoleKeys) {
        expect(dreamTeamRoleLabels[key], isNotNull, reason: 'missing label for $key');
      }
      // The wire key is social_analyst but the engine node label is "Sentiment Analyst".
      expect(dreamTeamRoleLabels['social_analyst'], 'Sentiment Analyst');
      // No stray labels beyond the 12 keys.
      expect(dreamTeamRoleLabels.keys.toSet(), dreamTeamRoleKeys.toSet());
    });

    test('DEEP_ROLES are exactly the two judges', () {
      expect(dreamTeamDeepRoles, {'research_manager', 'portfolio_manager'});
      expect(roleFallsBackToDeep('research_manager'), isTrue);
      expect(roleFallsBackToDeep('portfolio_manager'), isTrue);
      expect(roleFallsBackToDeep('market_analyst'), isFalse);
    });

    test('the 5 stages partition all 12 roles with none missing or duplicated', () {
      final grouped = [for (final (_, keys) in dreamTeamStages) ...keys];
      expect(grouped.length, 12, reason: 'a role is missing or duplicated across stages');
      expect(grouped.toSet(), dreamTeamRoleKeys.toSet());
      // Stage order is the engine pipeline order.
      expect([for (final (label, _) in dreamTeamStages) label],
          ['Analyst desks', 'Research debate', 'Trader', 'Risk team', 'Portfolio']);
    });

    test('tool-roles and structured-roles are valid, disjoint subsets of the 12', () {
      expect(dreamTeamToolRoles, {'market_analyst', 'news_analyst', 'fundamentals_analyst'});
      expect(dreamTeamStructuredRoles,
          {'social_analyst', 'research_manager', 'trader', 'portfolio_manager'});
      // Both are subsets of the roster.
      expect(dreamTeamToolRoles.difference(dreamTeamRoleKeys.toSet()), isEmpty);
      expect(dreamTeamStructuredRoles.difference(dreamTeamRoleKeys.toSet()), isEmpty);
      // A role is never both tool-gated and structured-gated.
      expect(dreamTeamToolRoles.intersection(dreamTeamStructuredRoles), isEmpty);
    });
  });
}
