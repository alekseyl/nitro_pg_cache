module NitroPgCache
  module ViewerExt
    def db_cache( item )
      if @current_cache_aggregator[:reverse] || !item.try(:nitro_cached_value)
        @current_cache_aggregator[:caches] << [item.id, yield]
      else
        safe_concat( item.nitro_cached_value )
      end
    end

    # I decided to keep both solutions reverse and straight. reverse is faster,
    # but straight is more srtaightforward :) and may be more stable, especially with DB sharding
    # also when using prerendering speed is the same and stability is preferable
    def db_cache_collection(options)

      if options[:collection].is_a?(ActiveRecord::Relation)

        whole_cache_key = options[:collection].try(:cache_key)
        cached_result = NitroCache.where( nitro_cache_key: whole_cache_key, nitro_cacheable_id: nil, nitro_cacheable_type: nil).first

        if cached_result
          cached_result.update_attributes(viewed_at: Time.now)
          return cached_result.try(:nitro_cached_value).try(:html_safe)
        end

        render_result = options[:straight_cache] ? db_cache_collection_s( options ) : db_cache_collection_r( options )

        # why not NitroCache.create( nitro_cached_value: render_result, nitro_cache_key: whole_cache_key, nitro_cacheable_id: nil, nitro_cacheable_type: nil) &
        # because on large collections raw insert is 1.2 faster, i.e. same speed as memcache.
        NitroCache.connection.execute( <<INSERT_STR
          INSERT INTO "nitro_caches" ("nitro_cached_value", "nitro_cache_key", "nitro_partial_id", "viewed_at" )
           VALUES ('#{render_result}', '#{whole_cache_key}', '#{@current_cache_aggregator[:nitro_partial_id]}', '#{Time.now}') RETURNING "id"
INSERT_STR
        )
        render_result
      else
        db_cache_array( options )
      end
    end

    # It's used ONLY for prerender purpose of single element collection: [elem]
    def db_cache_array( options )
      collection = options[:collection]
      # nitro_cache_key - same across all collection
      nitro_cache_key = options.to_nitro_cache_key

      # this is place where NitroPartial creates new partials info in DB
      @current_cache_aggregator = { nitro_partial_id: NitroPartial.get_partial( options[:partial], options ).id,
                                    nitro_cache_key: nitro_cache_key,
                                    reverse: false,
                                    caches: [] }

      result = render( partial: options[:partial],
                       collection: collection,
                       as: options[:as],
                       locals: {
                           locals: options[:locals]
                       }
      )
      (collection.try(:first) ? collection.try(:first).class : collection.klass).nitro_cache_bulk_insert( @current_cache_aggregator )

      NitroCache.where( nitro_cacheable: collection, nitro_cache_key: nitro_cache_key ).update_all(viewed_at: Time.now)
      result
    end

    # cache_key generated with cache_by and locals
    # straight cache. same logic as usual cache.
    def db_cache_collection_s( options )
      collection = options[:collection]
      # nitro_cache_key - same across all collection
      nitro_cache_key = options.to_nitro_cache_key
      result = ""

      aggr_result = collection.aggregate_collection( nitro_cache_key )
      if aggr_result['has_nulls'] == 't'
        # this is place where NitroPartial creates new partials info in DB
        @current_cache_aggregator = { nitro_partial_id: NitroPartial.get_partial( options[:partial], options ).id,
                                      nitro_cache_key: nitro_cache_key,
                                      reverse: false,
                                      caches: [] }

        result = render( partial: options[:partial],
                         #because of select nitro_cached_value we need to add select( 'all.*' )
                         collection: collection.select_all_if_empty
                                         .select_nitro_cache
                                         .outer_join_partials(nitro_cache_key),
                         as: options[:as],
                         locals: {
                             locals: options[:locals]
                         }
        )
        # Нужно массив все таки переделать в хеш на случай повторений в коллекции
        collection.klass.nitro_cache_bulk_insert( @current_cache_aggregator )

      else
        result = aggr_result['str_agg'].try(:html_safe)
      end

      #NitroCache.where( nitro_cacheable: collection, nitro_cache_key: nitro_cache_key) breaks on complex collections
      NitroCache.where( nitro_cacheable_type: collection.base_class,
                        nitro_cacheable_id: collection.base_class
                                                .from( "(#{collection.to_sql }) #{collection.table_name}" ).select(:id),
                        nitro_cache_key: nitro_cache_key )
          .update_all(viewed_at: Time.now)

      # alternative way to
      #ActiveRecord::Base.connection.execute( <<UPDATE_SQL
      #          UPDATE "nitro_cahes"
      #          SET "viewed_at" = '#{Time.now}'
      #          WHERE "nitro_partials"."id" IN (
      #             SELECT "nitro_caches"."id" FROM (#{collection.outer_join_partials(nitro_cache_key).unscope(:select).select('"nitro_caches"."id"').to_sql}) as db_cache_partials )
      # UPDATE_SQL
      #       )

      result
    end


    # 'reverse' cache: we first getting only noncached records, renders them, cache, and after that
    # aggregate whole collection from DB

    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # !! Может возникнуть проблема с шардами!!! поэтому вообще говоря
    #    ГЕТ при реверсном кешировании должен идти на мастер-шард!!!!
    #                                 ИЛИ
    # выяснить, если операция синхронная и возврат идет только после того как расползлось по шардам - тогда без разницы.
    # в принципе операция достаточно быстрая, так что может и разлететься, но с другой стороны может шарды отлетели от связи с главным.
    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    # вариант с кеш реверсом, сначала достаем те которые не отрисованы/закешированы,
    # отрисовываем их, и после этого делаем без всяких извратов аггрегацию
    def db_cache_collection_r( options )
      collection = options[:collection]
      # nitro_cache_key - same across all collection
      nitro_cache_key = options.to_nitro_cache_key

      @current_cache_aggregator = { nitro_partial_id: NitroPartial.get_partial( options[:partial], options ).id,
                                    nitro_cache_key: nitro_cache_key,
                                    reverse: true,
                                    caches: [] }
      # some how rails can't manage it through collection, so we downgrade it to collection.base_class
      # but it must go unscoped, default_scopes will be added from original collection
      render_collection = collection.base_class.unscoped
      collection.values.slice(:joins, :references, :includes).each{|key, value| render_collection = render_collection.send("#{key}", value) }

      render( partial: options[:partial],
              collection: render_collection.from( "(#{collection.outer_join_partials(nitro_cache_key)
                                                          .select_all_if_empty
                                                          .select_nitro_cache.to_sql }) #{collection.table_name}" )
                              .where(nitro_cached_value: nil),
              as: options[:as],
              locals: {
                  locals: options[:locals]
              }
      )

      collection.klass.nitro_cache_bulk_insert( @current_cache_aggregator ) unless @current_cache_aggregator[:caches].blank?

      # todo SHARD!
      # if @current_cache_aggregator[:caches].blank? than we can ask any shard, else only master shard

      #NitroCache.where( nitro_cacheable: collection, nitro_cache_key: nitro_cache_key ) - breaks :(
      NitroCache.where( nitro_cacheable_type: collection.base_class,
                        nitro_cacheable_id: collection.base_class.unscoped
                                                .from( "(#{collection.to_sql }) #{collection.table_name}" ).select(:id),
                        nitro_cache_key: nitro_cache_key ).update_all(viewed_at: Time.now)

      collection.aggregate_collection( nitro_cache_key )['str_agg'].try(:html_safe)
    end

  end
end