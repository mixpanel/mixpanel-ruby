require 'rspec'
require 'mixpanel-ruby/flags/utils'

describe Mixpanel::Flags::Utils do
  describe '.generate_traceparent' do
    it 'should generate traceparent in W3C format' do
      traceparent = Mixpanel::Flags::Utils.generate_traceparent

      # W3C traceparent format: 00-{32 hex chars}-{16 hex chars}-01
      # https://www.w3.org/TR/trace-context/#traceparent-header
      pattern = /^00-[0-9a-f]{32}-[0-9a-f]{16}-01$/

      expect(traceparent).to match(pattern)
    end
  end

  describe '.normalized_hash' do
    def expect_valid_hash(hash)
      expect(hash).to be_a(Float)
      expect(hash).to be >= 0.0
      expect(hash).to be < 1.0
    end

    it 'should match known test vectors' do
      hash1 = Mixpanel::Flags::Utils.normalized_hash('abc', 'variant')
      expect(hash1).to eq(0.72)

      hash2 = Mixpanel::Flags::Utils.normalized_hash('def', 'variant')
      expect(hash2).to eq(0.21)
    end

    it 'should produce consistent results' do
      hash1 = Mixpanel::Flags::Utils.normalized_hash('test_key', 'salt')
      hash2 = Mixpanel::Flags::Utils.normalized_hash('test_key', 'salt')
      hash3 = Mixpanel::Flags::Utils.normalized_hash('test_key', 'salt')

      expect(hash1).to eq(hash2)
      expect(hash2).to eq(hash3)
    end

    it 'should produce different hashes when salt is changed' do
      hash1 = Mixpanel::Flags::Utils.normalized_hash('same_key', 'salt1')
      hash2 = Mixpanel::Flags::Utils.normalized_hash('same_key', 'salt2')
      hash3 = Mixpanel::Flags::Utils.normalized_hash('same_key', 'different_salt')

      expect(hash1).not_to eq(hash2)
      expect(hash1).not_to eq(hash3)
      expect(hash2).not_to eq(hash3)
    end

    it 'should produce different hashes when order is changed' do
      hash1 = Mixpanel::Flags::Utils.normalized_hash('abc', 'salt')
      hash2 = Mixpanel::Flags::Utils.normalized_hash('bac', 'salt')
      hash3 = Mixpanel::Flags::Utils.normalized_hash('cba', 'salt')

      expect(hash1).not_to eq(hash2)
      expect(hash1).not_to eq(hash3)
      expect(hash2).not_to eq(hash3)
    end

    describe 'edge cases with empty strings' do
      it 'should return valid hash for empty key' do
        hash = Mixpanel::Flags::Utils.normalized_hash('', 'salt')
        expect_valid_hash(hash)
      end

      it 'should return valid hash for empty salt' do
        hash = Mixpanel::Flags::Utils.normalized_hash('key', '')
        expect_valid_hash(hash)
      end

      it 'should return valid hash for both empty' do
        hash = Mixpanel::Flags::Utils.normalized_hash('', '')
        expect_valid_hash(hash)
      end

      it 'empty strings in different positions should produce different results' do
        hash1 = Mixpanel::Flags::Utils.normalized_hash('', 'salt')
        hash2 = Mixpanel::Flags::Utils.normalized_hash('key', '')
        expect(hash1).not_to eq(hash2)
      end
    end

    describe 'special characters' do
      test_cases = [
        { key: '🎉', description: 'emoji' },
        { key: 'beyoncé', description: 'accented characters' },
        { key: 'key@#$%^&*()', description: 'special symbols' },
        { key: 'key with spaces', description: 'spaces' }
      ]

      test_cases.each do |test_case|
        it "should return valid hash for #{test_case[:description]}" do
          hash = Mixpanel::Flags::Utils.normalized_hash(test_case[:key], 'salt')
          expect_valid_hash(hash)
        end
      end

      it 'produces different results for different special characters' do
        hashes = test_cases.map { |tc| Mixpanel::Flags::Utils.normalized_hash(tc[:key], 'salt') }

        hashes.each_with_index do |hash1, i|
          hashes.each_with_index do |hash2, j|
            expect(hash1).not_to eq(hash2) if i != j
          end
        end
      end
    end
  end
end
