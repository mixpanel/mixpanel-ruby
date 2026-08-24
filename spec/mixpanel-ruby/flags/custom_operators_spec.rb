require 'rspec'
require 'json_logic'
require 'mixpanel-ruby/flags/custom_operators'

# Rule builders defined at the top level so the case tables below can be built
# while the describe blocks are being collected.
def var_node(key)
  { 'var' => key }
end

def semver_rule(key, sym, target)
  { 'semver_compare' => [var_node(key), sym, target] }
end

def datetime_rule(key, sym, target)
  { 'datetime_compare' => [var_node(key), sym, target] }
end

def custom_between(op, key, lo, hi)
  { 'and' => [
    { op => [var_node(key), '>=', lo] },
    { op => [var_node(key), '<=', hi] }
  ] }
end

def datetime_between(key, lo, hi)
  { 'and' => [
    { 'datetime_compare' => [var_node(key), '>=', lo] },
    { 'datetime_compare' => [var_node(key), '<=', hi] }
  ] }
end

describe Mixpanel::Flags::CustomOperators do
  def apply(rule, data)
    JsonLogic.apply(rule, data)
  end

  describe 'semver_compare' do
    [
      ['is, equal', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3' }, true],
      ['is, not equal', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.4' }, false],
      ['is not', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.4' }, true],
      ['less than, patch', semver_rule('app_version', '<', '1.2.3'), { 'app_version' => '1.2.2' }, true],
      ['less than, false', semver_rule('app_version', '<', '1.2.3'), { 'app_version' => '1.2.3' }, false],
      ['less or equal, boundary', semver_rule('app_version', '<=', '1.2.3'), { 'app_version' => '1.2.3' }, true],
      ['greater than, minor', semver_rule('app_version', '>', '1.2.3'), { 'app_version' => '1.3.0' }, true],
      ['greater or equal, boundary', semver_rule('app_version', '>=', '1.2.3'), { 'app_version' => '1.2.3' }, true],
      ['double-digit ordering (not lexical)', semver_rule('app_version', '>', '1.9.0'), { 'app_version' => '1.10.0' }, true],
      ['prerelease precedes release', semver_rule('app_version', '<', '1.0.0'), { 'app_version' => '1.0.0-alpha' }, true],
      ['lenient v-prefix', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'v1.2.3' }, true],
      ['lenient uppercase V-prefix', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'V1.2.3' }, true],
      ['v-prefix keeps prerelease', semver_rule('app_version', '<', '1.0.0'), { 'app_version' => 'v1.0.0-alpha' }, true],
      ['v-prefix, not equal', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => 'v1.2.4' }, true],
      ['v-prefix, at or below', semver_rule('app_version', '<=', '1.2.3'), { 'app_version' => 'v1.2.3' }, true],
      ['v-prefix, greater', semver_rule('app_version', '>', '1.2.3'), { 'app_version' => 'v1.2.4' }, true],
      ['v-prefix, at or above', semver_rule('app_version', '>=', '1.2.3'), { 'app_version' => 'v1.2.3' }, true],
      ['lenient minor-only target', semver_rule('app_version', '=', '1.2'), { 'app_version' => '1.2.0' }, true],
      # Every symbol is asserted in both directions.
      ['is not, equal', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3' }, false],
      ['less or equal, above', semver_rule('app_version', '<=', '1.2.3'), { 'app_version' => '1.2.4' }, false],
      ['greater than, below', semver_rule('app_version', '>', '1.2.3'), { 'app_version' => '1.2.2' }, false],
      ['greater or equal, below', semver_rule('app_version', '>=', '1.2.3'), { 'app_version' => '1.2.2' }, false],
      # Prerelease precedence, SemVer 2.0.0 section 11.
      ['prerelease alpha before beta', semver_rule('app_version', '<', '1.0.0-beta'), { 'app_version' => '1.0.0-alpha' }, true],
      ['prerelease beta before rc1', semver_rule('app_version', '<', '1.0.0-rc1'), { 'app_version' => '1.0.0-beta' }, true],
      ['prerelease rc1 before rc2', semver_rule('app_version', '<', '1.0.0-rc2'), { 'app_version' => '1.0.0-rc1' }, true],
      ['more prerelease fields wins', semver_rule('app_version', '<', '1.0.0-alpha.1'), { 'app_version' => '1.0.0-alpha' }, true],
      ['numeric identifier below alphanumeric', semver_rule('app_version', '<', '1.0.0-alpha.beta'), { 'app_version' => '1.0.0-alpha.1' }, true],
      ['fewer fields below alphanumeric', semver_rule('app_version', '<', '1.0.0-alpha.beta'), { 'app_version' => '1.0.0-alpha' }, true],
      ['numeric identifiers compare numerically', semver_rule('app_version', '<', '1.0.0-beta.11'), { 'app_version' => '1.0.0-beta.2' }, true],
      ['dotted identifier ordering, letters', semver_rule('app_version', '<', '1.0.0-b.1'), { 'app_version' => '1.0.0-a.1' }, true],
      ['dotted identifier ordering, digits', semver_rule('app_version', '<', '1.0.0-a.2'), { 'app_version' => '1.0.0-a.1' }, true],
      ['identical prereleases are equal', semver_rule('app_version', '=', '1.0.0-rc1'), { 'app_version' => '1.0.0-rc1' }, true],
      ['rc1 outranks dotted rc.1', semver_rule('app_version', '>', '1.0.0-rc.1'), { 'app_version' => '1.0.0-rc1' }, true],
      ['core version dominates prerelease', semver_rule('app_version', '>', '1.9.9'), { 'app_version' => '2.0.0-alpha' }, true],
      # A release outranks its own prerelease, asserted from both sides and under every symbol.
      ['release outranks its prerelease', semver_rule('app_version', '>', '1.0.0-alpha'), { 'app_version' => '1.0.0' }, true],
      ['release at or above its prerelease', semver_rule('app_version', '>=', '1.0.0-rc1'), { 'app_version' => '1.0.0' }, true],
      ['release differs from its prerelease', semver_rule('app_version', '!=', '1.0.0-alpha'), { 'app_version' => '1.0.0' }, true],
      ['prerelease differs from its release', semver_rule('app_version', '!=', '1.0.0'), { 'app_version' => '1.0.0-alpha' }, true],
      ['prerelease at or below its release', semver_rule('app_version', '<=', '1.0.0'), { 'app_version' => '1.0.0-alpha' }, true],
      ['prerelease of a higher core still wins', semver_rule('app_version', '>', '0.9.9'), { 'app_version' => '1.0.0-alpha' }, true],
      ['prerelease below the next patch', semver_rule('app_version', '<', '1.0.1'), { 'app_version' => '1.0.0-rc1' }, true],
      # Prerelease identifier comparison, SemVer 2.0.0 section 11.4.
      ['numeric identifiers are not compared lexically', semver_rule('app_version', '<', '1.0.0-10'), { 'app_version' => '1.0.0-2' }, true],
      ['numeric identifier ranks below alphanumeric', semver_rule('app_version', '<', '1.0.0-alpha'), { 'app_version' => '1.0.0-1' }, true],
      ['hyphen inside an identifier sorts by ascii', semver_rule('app_version', '<', '1.0.0-alpha-1'), { 'app_version' => '1.0.0-alpha' }, true],
      ['beta ranks below rc', semver_rule('app_version', '<', '1.0.0-rc.1'), { 'app_version' => '1.0.0-beta.11' }, true],
      ['last prerelease ranks below the release', semver_rule('app_version', '<', '1.0.0'), { 'app_version' => '1.0.0-rc.1' }, true],
      # Build metadata carries no precedence.
      ['build metadata ignored', semver_rule('app_version', '=', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, true],
      ['build metadata ignored with prerelease', semver_rule('app_version', '=', '1.0.0-alpha'), { 'app_version' => '1.0.0-alpha+build' }, true],
      ['build metadata with hyphen ignored', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3+build.1-2' }, true],
      # Ignored means equal, so every symbol has to agree with that.
      ['build metadata leaves versions equal', semver_rule('app_version', '!=', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, false],
      ['build metadata is not less', semver_rule('app_version', '<', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, false],
      ['build metadata is not greater', semver_rule('app_version', '>', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, false],
      ['build metadata at or below', semver_rule('app_version', '<=', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, true],
      ['build metadata at or above', semver_rule('app_version', '>=', '1.0.0+build2'), { 'app_version' => '1.0.0+build1' }, true],
      ['build metadata does not block ordering', semver_rule('app_version', '<', '1.0.1+build1'), { 'app_version' => '1.0.0+build9' }, true],
      ['build metadata does not block reverse ordering', semver_rule('app_version', '>', '1.0.0+build9'), { 'app_version' => '1.0.1+build1' }, true],
      # Partial versions keep their prerelease once zero-padded.
      ['partial version with prerelease', semver_rule('app_version', '=', '1.2.0-alpha'), { 'app_version' => '1.2-alpha' }, true],
      ['partial prerelease below later minor', semver_rule('app_version', '<', '1.3.1'), { 'app_version' => '1.2-alpha' }, true],
      ['partial prerelease below its release', semver_rule('app_version', '<', '1.2.0'), { 'app_version' => '1.2-alpha' }, true],
      ['major-only with prerelease', semver_rule('app_version', '<', '1.0.0'), { 'app_version' => '1-rc1' }, true],
      # An empty prerelease is invalid, so it is rejected rather than treated as the bare release.
      ['empty prerelease, no match', semver_rule('app_version', '=', '1.0.0'), { 'app_version' => '1.0.0-' }, false],
      ['empty prerelease, not-equal also false', semver_rule('app_version', '!=', '1.0.0'), { 'app_version' => '1.0.0-' }, false],
      ['empty prerelease on partial version, no match', semver_rule('app_version', '=', '1.2.0'), { 'app_version' => '1.2-' }, false],
      ['empty prerelease on partial version, not-equal also false', semver_rule('app_version', '!=', '1.2.0'), { 'app_version' => '1.2-' }, false],
      # Hyphens are legal inside a prerelease identifier, so these are NOT empty prereleases.
      ['trailing hyphen inside identifier', semver_rule('app_version', '<', '1.0.0'), { 'app_version' => '1.0.0-alpha-' }, true],
      # SemVer 2.0.0 forbids leading zeros in the core, so these are rejected rather than normalized.
      ['leading zero in major, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '01.2.3' }, false],
      ['leading zero in major, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '01.2.3' }, false],
      ['leading zero in minor, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.02.3' }, false],
      ['leading zero in minor, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.02.3' }, false],
      ['leading zero in patch, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.03' }, false],
      ['leading zero in patch, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.03' }, false],
      ['leading zeros throughout, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '01.02.03' }, false],
      ['leading zeros throughout, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '01.02.03' }, false],
      # A numeric prerelease identifier may not carry a leading zero either (section 9).
      ['numeric prerelease with leading zero, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3-01' }, false],
      ['numeric prerelease with leading zero, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3-01' }, false],
      ['dotted numeric prerelease with leading zero, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3-rc.01' }, false],
      ['dotted numeric prerelease with leading zero, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3-rc.01' }, false],
      # An alphanumeric identifier may contain digits, so this one stays valid.
      ['alphanumeric prerelease with digits', semver_rule('app_version', '<', '1.2.3'), { 'app_version' => '1.2.3-rc01' }, true],
      ['between, inside', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '1.5.0' }, true],
      ['between, low boundary inclusive', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '1.2.3' }, true],
      ['between, high boundary inclusive', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '2.0.0' }, true],
      ['between, below', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '1.0.0' }, false],
      ['between, above', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '2.0.1' }, false],
      # A prerelease sits below its own release, which decides both boundary cases.
      ['between, prerelease inside', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '1.5.0-rc1' }, true],
      ['between, prerelease below the high bound', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '2.0.0-rc1' }, true],
      ['between, prerelease of the low bound falls out', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => '1.2.3-rc1' }, false],
      ['between, invalid version', custom_between('semver_compare', 'app_version', '1.2.3', '2.0.0'), { 'app_version' => 'not-a-version' }, false],
      ['between, single-point range', custom_between('semver_compare', 'app_version', '1.2.3', '1.2.3'), { 'app_version' => '1.2.3' }, true],
      # Fail-closed: unparseable or missing values never match.
      ['invalid actual, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'not-a-version' }, false],
      ['non-string actual, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 123 }, false],
      ['missing property, no match', semver_rule('app_version', '=', '1.2.3'), {}, false],
      # A malformed version must never be padded or coerced into a real one. Both symbols are
      # asserted so that "accepted at all" is observable rather than masked by a single false.
      ['empty version, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '' }, false],
      ['empty version, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '' }, false],
      ['bare v, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'v' }, false],
      ['bare v, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => 'v' }, false],
      ['leading separator, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '-1.2.3' }, false],
      ['leading separator, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '-1.2.3' }, false],
      ['trailing dot, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.' }, false],
      ['trailing dot, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.' }, false],
      ['trailing dot after patch, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3.' }, false],
      ['trailing dot after patch, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3.' }, false],
      ['empty middle segment, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1..2' }, false],
      ['empty middle segment, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1..2' }, false],
      ['four components, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3.4' }, false],
      ['four components, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3.4' }, false],
      ['range prefix, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '^1.2.3' }, false],
      ['range prefix, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '^1.2.3' }, false],
      ['version inside text, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'abc1.2.3' }, false],
      ['version inside text, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => 'abc1.2.3' }, false],
      ['empty build metadata, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3+' }, false],
      ['empty build metadata, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3+' }, false],
      ['empty prerelease identifier, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3-alpha..1' }, false],
      ['empty prerelease identifier, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3-alpha..1' }, false],
      ['lone dot prerelease, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3-.' }, false],
      ['lone dot prerelease, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3-.' }, false],
      ['underscore in prerelease, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => '1.2.3-ALPHA_BETA' }, false],
      ['underscore in prerelease, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => '1.2.3-ALPHA_BETA' }, false],
      ['doubled v-prefix, no match', semver_rule('app_version', '=', '1.2.3'), { 'app_version' => 'vv1.2.3' }, false],
      ['doubled v-prefix, not-equal also false', semver_rule('app_version', '!=', '1.2.3'), { 'app_version' => 'vv1.2.3' }, false]
    ].each do |name, rule, data, want|
      it name do
        expect(apply(rule, data)).to eq(want)
      end
    end
  end

  # Epoch-millisecond constants (UTC instants) used as datetime targets,
  # matching the UI's emitted format.
  JUL16_MS = 1_784_160_000_000 # 2026-07-16T00:00:00Z
  JAN1_MS  = 1_767_225_600_000 # 2026-01-01T00:00:00Z
  DEC31_MS = 1_798_675_200_000 # 2026-12-31T00:00:00Z
  JUL16_END_MS = 1_784_246_399_999 # 2026-07-16T23:59:59.999Z
  LEAP_DAY_MS = 1_709_164_800_000 # 2024-02-29T00:00:00Z
  JUL16_INDIA_MS = 1_784_140_200_000 # 2026-07-16T00:00:00+05:30
  JUL16_PACIFIC_MS = 1_784_188_800_000 # 2026-07-16T00:00:00-08:00

  describe 'datetime_compare' do
    [
      # Asymmetric contract: subject (runtime var) is a strict RFC3339 string, target is epoch ms.
      ['before, true', datetime_rule('signup', '<', JUL16_MS), { 'signup' => '2026-07-15T00:00:00Z' }, true],
      ['before, false', datetime_rule('signup', '<', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Z' }, false],
      ['on (equal), true', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Z' }, true],
      ['not on, true', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-17T00:00:00Z' }, true],
      ['since (>=), boundary', datetime_rule('signup', '>=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Z' }, true],
      ['after (>), true', datetime_rule('signup', '>', JUL16_MS), { 'signup' => '2026-07-17T00:00:00Z' }, true],
      ['after (>), false', datetime_rule('signup', '>', JUL16_MS), { 'signup' => '2026-07-15T00:00:00Z' }, false],
      # Every symbol is asserted in both directions.
      ['at or before, boundary', datetime_rule('signup', '<=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Z' }, true],
      ['at or before, after', datetime_rule('signup', '<=', JUL16_MS), { 'signup' => '2026-07-17T00:00:00Z' }, false],
      ['on (equal), false', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-17T00:00:00Z' }, false],
      ['not on, equal', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Z' }, false],
      ['since (>=), before', datetime_rule('signup', '>=', JUL16_MS), { 'signup' => '2026-07-15T00:00:00Z' }, false],
      ['between, inside', datetime_between('signup', JAN1_MS, DEC31_MS), { 'signup' => '2026-06-15T00:00:00Z' }, true],
      ['between, low boundary inclusive', datetime_between('signup', JAN1_MS, DEC31_MS), { 'signup' => '2026-01-01T00:00:00Z' }, true],
      ['between, high boundary inclusive', datetime_between('signup', JAN1_MS, DEC31_MS), { 'signup' => '2026-12-31T00:00:00Z' }, true],
      ['between, before range', datetime_between('signup', JAN1_MS, DEC31_MS), { 'signup' => '2025-12-31T00:00:00Z' }, false],
      ['between, after range', datetime_between('signup', JAN1_MS, DEC31_MS), { 'signup' => '2027-01-01T00:00:00Z' }, false],
      ['negative epoch-ms target resolves to -1s', datetime_rule('signup', '=', -1500), { 'signup' => '1969-12-31T23:59:59Z' }, true],
      ['negative epoch-ms target, not equal', datetime_rule('signup', '!=', -1500), { 'signup' => '1969-12-31T23:59:59Z' }, false],
      ['negative epoch-ms target, at or after', datetime_rule('signup', '>=', -1500), { 'signup' => '1969-12-31T23:59:59Z' }, true],
      ['negative epoch-ms target, before', datetime_rule('signup', '<', -1500), { 'signup' => '1969-12-31T23:59:58Z' }, true],
      ['negative epoch-ms target, after', datetime_rule('signup', '>', -2500), { 'signup' => '1969-12-31T23:59:59Z' }, true],
      ['subject floors, it does not truncate', datetime_rule('signup', '=', -2000), { 'signup' => '1969-12-31T23:59:58.500Z' }, true],
      ['subject floors, not to -1s', datetime_rule('signup', '!=', -1000), { 'signup' => '1969-12-31T23:59:58.500Z' }, true],
      # A leap day is a real date.
      ['leap day', datetime_rule('signup', '=', LEAP_DAY_MS), { 'signup' => '2024-02-29T00:00:00Z' }, true],
      # Time-zone offsets change the instant.
      ['offset with half-hour minutes', datetime_rule('signup', '=', JUL16_INDIA_MS), { 'signup' => '2026-07-16T00:00:00+05:30' }, true],
      ['rfc3339 subject with offset', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T02:00:00+02:00' }, true],
      ['positive offset precedes utc midnight', datetime_rule('signup', '<', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+05:30' }, true],
      ['negative offset', datetime_rule('signup', '=', JUL16_PACIFIC_MS), { 'signup' => '2026-07-16T00:00:00-08:00' }, true],
      ['negative offset follows utc midnight', datetime_rule('signup', '>', JUL16_MS), { 'signup' => '2026-07-16T00:00:00-08:00' }, true],
      ['zero offset equals Z', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+00:00' }, true],
      # Sub-second precision is dropped, on both sides. The end-of-day rows are the window the UI
      # emits for a single date, whose upper bound carries .999.
      ['one-digit fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.5Z' }, true],
      ['three-digit fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.500Z' }, true],
      ['six-digit fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.123456Z' }, true],
      ['nine-digit fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.999999999Z' }, true],
      ['zero fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.0Z' }, true],
      ['fractional seconds truncated', datetime_rule('signup', '>=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.500Z' }, true],
      ['end-of-day target drops its .999', datetime_rule('signup', '=', JUL16_END_MS), { 'signup' => '2026-07-16T23:59:59Z' }, true],
      ['end-of-day target is an inclusive bound', datetime_rule('signup', '<=', JUL16_END_MS), { 'signup' => '2026-07-16T23:59:59Z' }, true],
      ['end-of-day, fractional subject too', datetime_rule('signup', '=', JUL16_END_MS), { 'signup' => '2026-07-16T23:59:59.999Z' }, true],
      ['end-of-day inclusive, fractional subject', datetime_rule('signup', '<=', JUL16_END_MS), { 'signup' => '2026-07-16T23:59:59.999Z' }, true],
      # Fractional on both sides: the shape the UI actually round-trips.
      # Trimming and lowercasing.
      ['lowercased subject with fraction', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16t00:00:00.500z' }, true],
      ['lowercased subject with offset', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16t02:00:00+02:00' }, true],
      ['whitespace-padded subject', datetime_rule('signup', '=', JUL16_MS), { 'signup' => ' 2026-07-16T00:00:00Z ' }, true],
      ['lowercased rfc3339 subject', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16t00:00:00z' }, true],
      # Shape violations, asserted under both = and != so that "accepted at all" is observable.
      # RFC 3339 also permits 24:00:00 as end-of-day. Platforms disagree on it, so no vector
      # asserts it either way.
      ['one-digit month, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-7-16T00:00:00Z' }, false],
      ['one-digit month, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-7-16T00:00:00Z' }, false],
      ['space separator, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16 00:00:00Z' }, false],
      ['space separator, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16 00:00:00Z' }, false],
      ['missing zone, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00' }, false],
      ['missing zone, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00' }, false],
      ['empty fraction, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.Z' }, false],
      ['empty fraction, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00.Z' }, false],
      ['offset without colon, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+0200' }, false],
      ['offset without colon, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+0200' }, false],
      ['short offset, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+02' }, false],
      ['short offset, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00+02' }, false],
      ['trailing junk, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Zextra' }, false],
      ['trailing junk, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00Zextra' }, false],
      ['basic format, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '20260716T000000Z' }, false],
      ['basic format, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '20260716T000000Z' }, false],
      ['zone after lowercase z, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00z00:00' }, false],
      ['zone after lowercase z, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00z00:00' }, false],
      ['comma fractional separator, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00,5Z' }, false],
      ['comma fractional separator, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00,5Z' }, false],
      # Fail-closed: subject must be an RFC3339 string, target must be an epoch-ms number.
      ['numeric subject, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => JUL16_MS }, false],
      ['target beyond representable range, no match', datetime_rule('signup', '=', 1e308), { 'signup' => '2026-07-16T00:00:00Z' }, false],
      ['target beyond representable range, greater-than also false', datetime_rule('signup', '>', 1e308), { 'signup' => '2026-07-16T00:00:00Z' }, false],
      ['target beyond representable range, less-than also false', datetime_rule('signup', '<', 1e308), { 'signup' => '2026-07-16T00:00:00Z' }, false],
      ['bare date subject, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16' }, false],
      ['bare date subject, not-equal also false', datetime_rule('signup', '!=', JUL16_MS), { 'signup' => '2026-07-16' }, false],
      ['zoneless datetime subject, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => '2026-07-16T00:00:00' }, false],
      ['non-datetime string, no match', datetime_rule('signup', '=', JUL16_MS), { 'signup' => 'yesterday' }, false],
      ['missing property, no match', datetime_rule('signup', '=', JUL16_MS), {}, false]
    ].each do |name, rule, data, want|
      it name do
        expect(apply(rule, data)).to eq(want)
      end
    end
  end
end
