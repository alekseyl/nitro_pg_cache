 class AddNitroCacheTables < ActiveRecord::Migration
  def change
    create_table :nitro_caches do |t|
      t.text :key
      t.text :nitro_cached_value

      t.references :nitro_cacheable, polymorphic: true, index: { name: :index_nitro_cacheable_relations }
      t.references :nitro_partial, index: true

      # we don't need index here IF we never expire cache! also
      # since we use cron job to remove expired indexes, when index starts to cost lot we may omit
      t.datetime :viewed_at, index: true
    end

    add_index :nitro_caches, [:nitro_cacheable_id, :nitro_cacheable_type, :key], name: :merged_nitro_cacheable_index, unique: true
    add_index :nitro_caches, :nitro_cache_key, where: 'nitro_cacheable_id = NULL AND nitro_cacheable_type = NULL'

    create_table :nitro_partials do |t|
      t.text :partial, index: true
      t.boolean :prerender
      t.string :expires
      t.integer :record_limit, limit: 8
      t.string :partial_hash, index: true
      t.string :render_as
      t.column :cache_keys, :jsonb, default: {},  null: false

      t.timestamps null: false
    end

    add_index :nitro_partials, :cache_keys, using: :gin

  end
end
