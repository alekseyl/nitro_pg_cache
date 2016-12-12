# == Schema Information
#
# Table name: nitro_partials
#
#  id           :integer          not null, primary key
#  partial      :text
#  prerender    :boolean
#  expires      :string
#  record_limit :integer
#  partial_hash :string
#  cache_keys   :jsonb            default({}), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  render_as    :string
#
# Indexes
#
#  index_nitro_partials_on_cache_keys    (cache_keys)
#  index_nitro_partials_on_partial       (partial)
#  index_nitro_partials_on_partial_hash  (partial_hash)
#

# cache_keys has very special structure:
# { locals: { some_keys_combination } } then hash stored in cache_keys column will have this structure:
# { some_keys_combination.to_nitro_cache_key => some_keys_combination } assuming this:
# cache_keys.keys is the Array of all cache_keys for selected partial.
#
#
class NitroPartial < ActiveRecord::Base
  PRERENDER_BATCH = 1000
  EXPIRES_REGEX = /^\d+\.(day|days|week|weeks|month|months|year|years)\.from_now$/

  has_many :nitro_caches, dependent: :delete_all
  @@partials_cache = nil
  @@partials_scopes = {}

  scope :prerender, ->() { where(prerender: true) }

  class << self

    # вытягивает из БД все в переменную класса, чтобы лишний раз не вставать. в процессе этого проверяет не поменялось
    # ли что-нибудь внутри файлов
    def partials_cache
      if @@partials_cache.nil?
        all.each do |cp|
          # file was removed
          if File.exist?("#{Rails.root}/#{cp.partial_path}")
            # file hash changed
            if cp.partial_cache_invalid?
              # we are not update_caches even in prerender. cache updates in special rake
              cp.remove_caches
              cp.update_attributes( partial_hash: partial_hash(cp.partial) )
            end
          else
            cp.destroy
          end
        end
      end

      @@partials_cache ||= all.reload.map{ |cp| [cp.partial, cp] }.to_h
    end

    # scopes for prerender
    def partials_scopes
      @@partials_scopes
    end

    def all_key_combinations( all_locals, partial )
      return { {partial: partial}.to_nitro_cache_key => {} } if all_locals.blank?
      # Example for code below:
      # locals = {:role=>[:user, :admin], :public=>[true, false]}
      #
      # transforms into 4 combinations of possible keys:
      #
      # key_combinations = [{:public=>true, :role=>:user},
      #                     {:public=>true, :role=>:admin},
      #                     {:public=>false, :role=>:user},
      #                     {:public=>false, :role=>:admin}]
      #
      # i.e. we can now do
      # key_combinations.each do |kc|
      #    render partial: partial, locals: { record_as: record_as }.merge!( kc )  }
      # end
      key_combinations = all_locals.keys.map{|key| (all_locals[key].is_a?(Array) ? all_locals[key]: [all_locals[key]]).map{|val| { key => val } }  }
      key_combinations = key_combinations.pop.product(*key_combinations)
      key_combinations.map!{|key_arr| key_arr.inject({}){|memo, curr| memo.merge(curr) } }
      key_combinations.map{|locals_set| [locals_set.merge(partial: partial).to_nitro_cache_key, locals_set ]}.to_h
    end

    # prerender will not start with rails, because it may need large amount of time
    def add_prerendered_partial( options )
      existing_partial = partials_cache[options[:partial]] || where( partial: options[:partial] ).first
      key_combinations = options[:key_combinations] || all_key_combinations( options[:all_locals], options[:partial] )
      partials_scopes[options[:partial]] = options[:scope]

      raise( ArgumentError, 'expires params must be in form: N.(day[s]|week[s]|month[s]|year[s]).from_now' ) if !options[:expires].blank? || EXPIRES_REGEX === options[:expires].to_s
      raise( ArgumentError, 'must have scope for prerendering' ) unless options[:scope]

      if existing_partial
        # all non existed now key combination will be deleted
        existing_partial.nitro_caches.where.not( nitro_cache_key: key_combinations.keys ).delete_all

        existing_partial.update_attributes(
            render_as: options[:as],
            cache_keys: key_combinations,
            expires: options[:expires].to_s,
            prerender: true )

        existing_partial
      else
        partials_cache[options[:partial]] = create(
            cache_keys: key_combinations,
            expires: options[:expires].to_s,
            prerender: true,
            render_as: options[:as],
            partial: options[:partial],
            partial_hash: partial_hash( options[:partial] ) )
      end

    end

    # получить паршиал или создать ( для обычных кешей без пререндеринга, для пререндеринга, надо вызывать
    # add_prerendered_partial в модели которой пререндеринг прикрепляется )
    def get_partial( partial_name, options )
      # we need where first because rails can be run in parallels so it could be created already elsewhere
      partials_cache[partial_name] ||= where( partial: partial_name ).first || create( options.with_indifferent_access
                                                 .merge(
                                                     partial: partial_name,
                                                     render_as: options[:as],
                                                     partial_hash: partial_hash( partial_name ) )
                                                 .slice(*NitroPartial.column_names) )
    end

    def partial_hash( partial )
      Digest::SHA512.file( "#{Rails.root}/#{partial_path(partial)}" ).hexdigest
    end


    def partial_path(partial)
      # extract partial file name
      rg = /[^\/]*$/
      "app/views/#{partial.gsub( partial[rg], "_#{partial[rg]}" )}"
    end

  end

  def get_scope
    self.class.partials_scopes[partial]
  end

  # append_view_path
  def partial_cache_invalid?
    self.class.partial_hash(partial) != partial_hash
  end

  def remove_caches
    nitro_caches.delete_all
  end

  def update_caches( progress = nil )
    (get_scope.count/PRERENDER_BATCH + 1).times do |i|
      update_cache_for_collection( get_scope.limit(PRERENDER_BATCH).offset(i*PRERENDER_BATCH), progress )
    end
  end

  def update_cache_for_collection( collection, progress = nil )

    nitro_caches.where( nitro_cacheable: collection ).delete_all
    cache_keys.values.each do |locals|
      progress.try(:inc)
      ApplicationController.render( assigns: {
                                        locals: locals,
                                        partial: partial,
                                        render_as: render_as,
                                        rel: collection },
                                    inline: '<% db_cache_collection( straight_cache: false, collection: @rel, partial: @partial, as: @render_as, locals: @locals )%>' )
    end
  end

  def partial_path
    self.class.partial_path(partial)
  end

  #causes to break with connection pool error
  #partials_cache
end
