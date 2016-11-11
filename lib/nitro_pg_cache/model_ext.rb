module NitroPgCache
  module ModelExt
    extend ActiveSupport::Concern

    included do
      #
      after_save  :clear_nitro_cache
      after_touch :clear_nitro_cache

    end

    module ClassMethods
      # since it will be wrapped in scoping we can implement it as model class method not the relation methods
      def aggregate_collection(locals_key)
        # we can't use NitroCache.where( nitro_cache_key: nitro_cache_key, nitro_cacheable: self )
        # because we will lose collection order!
        # why use connection.execute instead of doing self.select also because of an order. if you using some order on your scope
        # than columns you using to order must appear in the GROUP BY clause or be used in an aggregate function or you will get an error
        connection.execute( <<AGGREGATE_STR
          SELECT string_agg( nitro_cached_value, '') as str_agg,
                 bool_or( nitro_cached_value is null ) as has_nulls
            FROM (#{self.select_nitro_cache.outer_join_partials(locals_key).to_sql}) as db_cache
AGGREGATE_STR
        )[0]
      end

      def select_all_if_empty
        all.select_values.blank? ? select( "#{table_name}.*" ) : all
      end

      def nitro_cache_bulk_insert( options )
        return if options[:caches].blank?
        # "nitro_cache_key", "nitro_cacheable_type", "viewed_at" - all same for entire collection
        last_tail = "'#{options[:nitro_cache_key]}', '#{self}', '#{Time.now}', '#{options[:nitro_partial_id]}'"
        tail = ", #{last_tail} ), ("
        # this is practically Values String without last tail and external enclosing brackets
        values = options[:caches].map{ |id_value| "#{id_value[0]}, $$#{id_value[1]}$$" }.join( tail )
        sql = <<INSERT
        INSERT INTO nitro_caches ("nitro_cacheable_id", "nitro_cached_value", "nitro_cache_key", "nitro_cacheable_type", "viewed_at", "nitro_partial_id")
        VALUES ( #{values}, #{last_tail}  )
        ON CONFLICT (nitro_cacheable_id, nitro_cacheable_type, nitro_cache_key)
        DO UPDATE SET nitro_cached_value = EXCLUDED.nitro_cached_value
INSERT
        ActiveRecord::Base.connection.execute( sql )
      end

      def select_nitro_cache
        select( ['nitro_caches.nitro_cached_value as nitro_cached_value'] )
      end

      #prepare for aggregation
      def outer_join_partials(cache_key)
        joins(<<JOIN
              LEFT OUTER JOIN "nitro_caches"
                   ON "nitro_caches"."nitro_cacheable_id" = "#{table_name}"."id"
                   AND "nitro_caches"."nitro_cacheable_type" = '#{base_class.to_s}'
                   AND "nitro_caches"."nitro_cache_key" = '#{cache_key}'
JOIN
        )
      end

      # add partial to prendering
      # options: { partial: , all_locals:, record_as: , partial: , scope:  }
      # partial: path to partial from Rails.root
      # all_locals: array of hashes of possible cache_keys|locals_name, {locals_name: [value1, value2], locals_name: [ value3, value4 ]}  see example below
      # prerender: true/false, flag that indicates does or doesn't this partial will be prerendered when a record changes, it's
      # expires: [/^\d+\.(day|days|week|weeks|month|months|year|years)\.from_now$/] as string N.(day[s]|week[s]|month[s]|year[s]).from_now
      # record_as: :symbol , if we prerendering than we pass locals
      # scope: scope wich is used for prerendering purpose, you may want to add some includes to it, same as includes in your controller action
      #
      # Example:
      # prerender_cache_partial(
      #   partial: 'app/views/products/product'
      #   locals: {:role=>[:user, :admin], :public=>[true, false]},
      #   scope: Model.where(created_at: -6.month.from_now..Time.now)
      # )
      #todo перед eval(expires) все равно сделать проверку. а то иначе можно положить исполняемую строку в БД и потом вынудить исполнится на прогоне )

      def add_prerender_partial(options)
        p_partial = NitroPartial.add_prerendered_partial( { scope: all }.merge(options) )
        after_commit { p_partial.update_cache_for_collection([self]) }
      end

    end

    def clear_nitro_cache
      NitroCache.where(nitro_cacheable: self).delete_all
    end
  end
end
