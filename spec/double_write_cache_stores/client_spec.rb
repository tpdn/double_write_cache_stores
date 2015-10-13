require 'spec_helper'

describe DoubleWriteCacheStores::Client do
  let :read_and_write_store do
    ActiveSupport::Cache.lookup_store :dalli_store, 'localhost:11211'
  end

  let :write_only_store do
    ActiveSupport::Cache.lookup_store :dalli_store, 'localhost:21211'
  end

  describe '#initialize' do
    it 'different cache store instance' do
      expect{ DoubleWriteCacheStores::Client.new read_and_write_store, 'bad instance object' }.to raise_error RuntimeError
    end
  end

  let :copy_cache_store do
    DoubleWriteCacheStores::Client.new read_and_write_store, write_only_store
  end

  let :one_cache_store do
    DoubleWriteCacheStores::Client.new read_and_write_store, nil
  end

  describe '#write' do
    before do
      copy_cache_store.write 'key', 'example-value', :expires_in => 1.day
    end
    it 'set value to multi store' do
      expect(read_and_write_store.read 'key').to eq 'example-value'
      expect(write_only_store.read 'key').to eq 'example-value'
    end
  end

  describe '#increment_cache_store'do
    let(:key) {'key-increment'}
    before { cache_store.delete key }

    context 'when cache_store has single cache' do
      let(:cache_store) { one_cache_store }
      context 'when value does not exist' do
        it 'set value' do
          cache_store.increment key, 1, :expires_in => 1.day
          expect(read_and_write_store.read key).to eq '1'
        end
      end
      context 'when numeric value exists' do
        before do
          cache_store.set key, 1, :expires_in => 1.day, :raw => true
        end
        it 'increase value' do
          cache_store.increment key, 1, :expires_in => 1.day
          expect(read_and_write_store.read key).to eq '2'
        end
      end
    end

    context 'when cache_store has double cache' do
      let(:cache_store) { copy_cache_store }
      context 'when value does not exist' do
        it 'set value' do
          cache_store.increment key, 1, :expires_in => 1.day
          expect(read_and_write_store.read key).to eq '1'
          expect(write_only_store.read key).to eq '1'
        end
      end
      context 'when numeric value exists' do
        before { cache_store.set key, 1, :expires_in => 1.day, :raw => true }
        it 'increase value' do
          cache_store.increment key, 1, :expires_in => 1.day
          expect(read_and_write_store.read key).to eq '2'
          expect(write_only_store.read key).to eq '2'
        end
      end
    end
  end

  shared_examples "cache store example" do |cache_store|
    describe '#read_multi' do
      before do
        cache_store.write 'key-a', 'example-value-a', :expires_in => 1.day
        cache_store.write 'key-b', 'example-value-b', :expires_in => 1.day
      end

      after { cache_store.flush }

      it 'get multi-keys values from multi store' do
        results = cache_store.read_multi('key-a', 'key-b', 'key-c')
        expect(results['key-a']).to eq 'example-value-a'
        expect(results['key-b']).to eq 'example-value-b'
        expect(results['key-c']).to eq nil
      end

      it 'returns values equal #get_multi' do
        expect(cache_store.read_multi('key-a', 'key-b')).to eq cache_store.get_multi('key-a', 'key-b')
      end
    end

    describe '#fetch' do
      before do
        cache_store.write 'key-a', 'example-value-a', :expires_in => 1.day
      end

      after { cache_store.flush }

      it 'returns value' do
        expect(cache_store.fetch('key-a')).to eq 'example-value-a'
        expect(cache_store.fetch('key-nil')).to eq nil
      end

      it 'get value and set value, block in args' do
        expect(cache_store.fetch('key-b')).to eq nil

        cache_store.fetch('key-b') do
          'block-value-b'
        end

        expect(cache_store.fetch('key-b')).to eq 'block-value-b'
        expect(cache_store.get('key-b')).to eq 'block-value-b'

        result = cache_store.fetch('key-b') do
          'not-overwrite-value'
        end
        expect(cache_store.fetch('key-b')).to eq 'block-value-b'
        expect(cache_store.get('key-b')).to eq 'block-value-b'
      end
    end

    describe '#delete' do
      before do
        copy_cache_store.write 'will-delete-key', 'example-will-delete-value', :expires_in => 1.day
      end
      it 'delete key-value' do
        expect(read_and_write_store.read 'will-delete-key').to eq 'example-will-delete-value'
        expect(write_only_store.read 'will-delete-key').to eq 'example-will-delete-value'

        copy_cache_store.delete 'will-delete-key'

        expect(read_and_write_store.read 'will-delete-key').to be_nil
        expect(write_only_store.read 'will-delete-key').to be_nil
      end
    end

    describe '#touch' do
      let(:expire_ttl) { 1 }

      before do
        cache_store.set 'touch-key', 'touch-value', :expires_in => expire_ttl
      end

      it 'expired value, not touched' do
        sleep expire_ttl
        expect(cache_store.read 'touch-key').to eq nil
      end

      it 'expired value, touched expired' do
        expect(cache_store.touch 'touch-key', expire_ttl).to be true
        sleep expire_ttl
        expect(cache_store.read 'touch-key').to eq nil
      end

      it 'returns value, before touched key' do
        expect(cache_store.touch 'touch-key').to be true
        sleep expire_ttl
        expect(cache_store.read  'touch-key').to eq 'touch-value'
      end
    end

    describe '#read' do
      before do
        cache_store.write 'key', 'example-read-value', :expires_in => 1.day
      end
      it 'returns writed value' do
        expect(cache_store.read 'key').to eq 'example-read-value'
      end
      it 'returns nil, not writed value' do
        expect(cache_store.read 'not-set-key').to eq nil
      end
    end

    describe '#flush' do
      before do
        copy_cache_store.write 'will-flush-key', 'will-flush-value', :expires_in => 1.day
      end
      it 'example' do
        expect(copy_cache_store.read 'will-flush-key').to eq 'will-flush-value'
        expect(copy_cache_store.flush).to eq true
        expect(copy_cache_store.read 'will-flush-key').to eq nil
      end
    end

    describe '#[]=(key,value) and get #[](key)' do
      it 'set value and get value' do
        cache_store['key'] = 'example-value'
        expect(cache_store['key']).to eq 'example-value'
      end
    end

    describe 'cas' do
      describe '#get_cas' do
        before do
          cache_store.set_cas 'get-cas-key', 'get-cas-value'
        end

        it 'example' do
          expect(cache_store.get_cas('get-cas-key')[0]).to eq 'get-cas-value'
          expect(cache_store.get_cas('get-cas-key')[1]).to be_kind_of(Integer)
        end
      end

      describe '#set_cas' do
        let :cas_unique do
          cache_store.set_cas('set-cas-key', 'set-cas-value')
          cache_store.get_cas('set-cas-key')[1]
        end

        it 'example' do
          expect(cache_store.set_cas('set-cas-key', 'set-cas-value', cas_unique)).to be_kind_of(Integer)
        end

        it 'returns false, not set cache because different cas_unique' do
          expect(cache_store.set_cas('set-cas-key', 'set-cas-value', cas_unique - 1)).to eq false
        end
      end
    end
  end

  describe "shard example" do
    context "ActiveSupport :dalli_store" do
      read_and_write_store = ActiveSupport::Cache.lookup_store :dalli_store, 'localhost:11211'
      write_only_store = ActiveSupport::Cache.lookup_store :dalli_store, 'localhost:21211'

      context "double cache store" do
        copy_cache_store = DoubleWriteCacheStores::Client.new(read_and_write_store, write_only_store)
        it_behaves_like "cache store example", copy_cache_store
      end

      context "one cache store object" do
        one_cache_store = DoubleWriteCacheStores::Client.new(read_and_write_store, nil)
        it_behaves_like "cache store example", one_cache_store
      end
    end

    context "Dalli::Client" do
      options = { :namespace => "app_v1", :compress => true }
      read_and_write_store = Dalli::Client.new('localhost:11211', options)
      write_only_store = Dalli::Client.new('localhost:21211', options)

      context "double cache store" do
        copy_cache_store = DoubleWriteCacheStores::Client.new(read_and_write_store, write_only_store)
        it_behaves_like "cache store example", copy_cache_store
      end

      context "one cache store" do
        one_cache_store = DoubleWriteCacheStores::Client.new(read_and_write_store)
        it_behaves_like "cache store example", one_cache_store
      end
    end
  end
end
