# Направление для возможной дальнейшей оптимизации первого рендеринга:
#
# паралельный рендеринг коллекции неоткешированных элементов, в силу того что нам не надо морочить голову с очерендностью рендеринга,
# можно параллельно отрендерить N подколлекций и бабахнуть это на БД одним запросом, более того GIL не должен
# мешать потому что он не пересекаются и пр.
#
# Актуально если мы не можем использовать prerender ( например у нас комбинаций ключей получается оч много )
# НО менее актуально если мы используем пререндер,
# потому что нам в таком случае не нужен космос по скорости потому что обновление можно пускать в отдельном треде
#
# Также возможно: автоматическое получение параметров с которых начинает иметь смысл парарллелить
#
# Еще одна наприер возможность разгона рельсового приложения с получением коллекций: nginx-sql модуль, если коллекция будет получаться
# отдельным запросом это можно вытащить в nginx модуль.

#                                      ВОЗМОЖНОСТИ БИБЛИОТЕКИ
# Реализованные возможности*:
# (* величины указаны при использовании гема pg_cache_key для реализации cache_key у коллекций,
#   поэтому в 4-х рельсах nitro_cache получает еще +20% выигрыша по времени, если pg_cache_key не исопльзуется, даже на полностью кешированной коллекции, см 6) )
# 1. Первичный рендеринг быстрее чем у memcache+dalli на ~10% для коллекции ( Это малоактуально если рендеринг коллекции занимает
#     менее 50% от рендеринга всей страницы, т.е. выигрыш на всей странице становится ~ 5% )
# 2. Пересортировка или рендеринг подколлекций на закешированной матрешкой коллекции в 2-3 и более раз быстрее ( чем больше коллекция тем больше выигрыш )
# 3. Возможность пререндеринга для элементов, т.е. при обновлении кешируемого элемента его кеши обновляются автоматом + спец рейк на их первичную генерацию
#  3.a Возможность пререндеринга только для определенного scope элементов.
# 4. Управление кешем на уровне БД без необходимости трогать объекты. NitroCache.where(nitro_cacheable: collection).delete_all и пр.
# 5. В четвертых рельсах, если не использовать pg_cache_key дополнительно выигрывает 25% времени от memcached+dalli
# 6. Можно легко переключать между обычным кешем и бд кешем. используя cache_by ?

# Нереализованные пока
# 7. БД Шардинг
# 8 Авторекеш. Возможно в дальнейшем автоматичечки перекешировывать существующие кеши без использования prerender - true, а с сохранением к каждому
#   ключу еще и Json для локалс.
# 9 Устаревание И лимитирование кешей. Может быть реализовано многими способами.

#                                     FEATURES
# Already working*:
#(* all benchmark numbers are given with pg_cache_key gem enabled, this mean that in rails < 5, you'll get +20% additional speed bonus for cached collection )
# 1. First rendering is faster then memcache+dalli on same machine. ~10% faster
# 2. Reordering and sub-collection rendering on cached collection are 2-3 times faster then memcached+dalli
#    Rendering are done with DB speed i.e. You can assume that feed rendering speed now are some very small time constant. 100 and 1K records are rendering with
#   ~0.01s difference
#   ( partially rendered subcollection is a superposition of 1.15 and 2-3 times, depends of non-cached elems amount )
# 3. You can enable prerendering for any scope of your DB records ( if you has a reasonable amount of different keys|locals sets per db record )
# 4. Agile managing of your cache because it's in DB now, you for example don't need to touch elems to remove
#   their cache you can do: NitroCache.where(nitro_cacheable: collection).delete_all
# 5. In 4.x rails if you don't use pg_cache_key, but use nitro_cache then you get additional +25% speedup for completly cached feed
# 6. Easily can switch back and forth from usual cache to db cache using cache_by key.
#
# Can be done soon
# 7 Shards DB
# 8 auto-renewable cache. we can save locals to jsonb column, after touching cached-element we can rerender
#    all dependent caches with saved locals. ( must check how mass update will suffer from json insert ).
# 9 Expiring and quantity limits, cache expiring can be done on different conditions including last time viewed.

#                                 ОГРАНИЧЕНИЯ:
#
# Только чистый кеш на коллекцию может исопльзоваться с данной библиотекой:
# Может быть сконвертированно:
#     -cache [@records, locals] do
#       =render partial: 'record', collection: @records, locals: locals
#
# Не получится сконвертировать без изменений ( придется разделить коллекцию и футер)
#     -cache [@records, locals ] do
#       =render partial: 'record', collection: @records, locals: locals
#       =render partial: 'pagination_footer', records: @records
#
#
#                                 RESTRICTIONS:
#
# 1 Only clear collections rendering can be cached with this gem. i.e.:
#   Can convert:
#     -cache [@records, locals ] do
#       =render partial: 'record', collection: @records, locals: locals
#
#   Can't convert ( you will need to split it )
#     -cache [@records, locals ] do
#       =render partial: 'record', collection: @records, locals: locals
#       =render partial: 'pagination_footer', records: @records
#
#
#                                       ИСПОЛЬЗОВАНИЕ ПАМЯТИ
# Объем используемой памяти примерно одинаковый и может зависеть от того какой конкретно пришел запрос, сколько в нем уже
# закешированных элементов сколько новых и пр.
#
#                                      MEMORY USAGE
#
# I didn't make a special comparision, but I assume that there is a little difference between usual cache and pg_cache,
# for example usual matroska-cache for collection which hasn't a cache for whole collection will bring N string concatenation
# and pg_cache will get result in one string from DB, and don't need reallocation for string.
# But in other cases pg_cache may need some additional concatenation against usual cache.
#
#                                     BENCHMARK
#
# Comparisons were made manually with rack mini-profiler gem +
# I used htop system-monitor to be sure that nothing going in the background and tempering with results
#
# CONFIGURATION: dalli + memcached same machine vs postgres 9.4 same machine ( ~ 8 logical cores + 10Gb )
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    ATTENTION NOTICE:   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# This numbers just a VERY particular case, you even can't use them to predict your own comparative numbers,
# not to say your own time in seconds! But I did it on two completly different tables and their collections and get very closed
# result in percents meaning that numbers are quite representative
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# real results on browser page first time render all N records ( linear dependency )
# first column - records count
# rv - "reverse" cache when we first just render only __missing__ elements and save them to DB, and second aggregate all collection from db
# dbs - data base straight mean it's render's with one straightforward iteration
# mmch - usual matroska doll cache with memcached and dalli
#
# ______________________________________FIRST RENDER_____________________________________
# 1K    rv ~ 14.7s dbs ~ 16s  mmch ~ 17s (~1.15 faster)
# 0.38K rv ~ 4.9   dbs ~ 5.2  mmch ~ 5.6
# 0.1K  rv ~ 1.3   dbs ~ 1.4  mmch ~ 1.5s (~1.15 faster)
#
# ____________FIRST RENDER SUBCOLLECTION/REORDERING (i.e. when all elements are cached, but not whole collection)___________________
# 1K    rv ~ 0.5s mmch ~ 1.5s  ( ~3 times faster )
# 0.38K rv ~ 0.35+s  mmch ~ 0.75+ ( ~2 times faster )
# 0.12K  rv ~ 0.2-0.25  mmch ~ 0.4-0.5+s ( ~2 times faster )
#
# ____________PARTIAL COLLECTION RENDERING______________________________________________
# We can assume this is superposition of already obtained numbers. i.e inside range: 1.15-3
# ( the right borders number depends on the collection size, the bigger collection bigger the number )
#
# ____________GETTING COLLECTION CACHE ( whole collection cached ( nitro wins cause it's not need to instantinate collection ) )__________
#Notice: if you use usual cache but with rails 5 or pg_cache_key gem it will bring nearly same result ( may be different in couple of 0.01s )
# 1K    rv ~ 0.5s mmch ~ 1s  ( ~2 times faster )
# 0.38K rv ~ 0.35+s  mmch ~ 0.6 ( ~1.7 times faster )
# 0.12K  rv ~ 0.2-0.25  mmch ~ 0.38s ( ~1.7 times faster )
#
#
# Дальше:
#   0) Нужно config в рельсах приделать. по аналогии с конфигом для дали например.
#   0.1) Naming нужно окончательный нейминг сделать.
#       Варианты:
#           gem: pg_nitro_cache
#           model: Partial: NitroPartial
#                  Cache:   NitroCache ( nitro_cache_value, nitro_cache_key, nitro_cacheable )

#   0.2) Привести миграции к правильному неймингу.

# prerender test:
#   1) выписать какие из вариантов для пререндеринга не прошли
#      пользовательского тестирования, проверить работу с комбинациями ключей
#   2) Система обновления db_cache ( нужно будет сделать нормальный прогресс для этого, потому что задача длинная. )
#       гем для этого я уже поставил и даже учел это в рейке, НО оно будет считать только по уникальным ключам шаги, а не по количеству записей.
#       Вариант: вынести получение незакешированной части коллекции в отдельный метод, получить общее количество незакешированных элементов,
#               переопределить рядом в рейке db_cache с вызовом inc на прогресс внутри.
#   3) устаревание expires?
#
#                                            GENERAL FALLBACK
# With any variant of prerender true/false all not found, caches get themselves cached usual way as in prerender-false case
#
#                                            ОСНОВНОЕ ПОВЕДЕНИЕ ПО УМОЛЧАНИЮ
# Независимо от того стоит prerender-true или нет, если на момент запроса значение cache_value пустое,
# то кеширование запускается обычным ходом, который совпадает, с вариантом когда prerender-false.
#
#
#                                 HOW IT BEHAVE WHEN SOMETHING CHANGES ( KEYS, PARTIALS, ETC )
# The main rule of thumb: no prerendering at server start, only mass cleaning old and creating new nitro_partial records!
# If you are using prerender, then run rake task prerender in parallel manually or by any automation script
# The rules of cache changes are depended on prerender state of partial true|false
# 1 Object changes:
#   а) prerender-true => after_commit -> render all locals variants
#   б) prerender-false => after_commit -> clear all caches
# 2 Cache params changes:
#   +2.1 New keys added.
#       true => rails started as usual, you run prerender rake manually!!,
#       false => do nothing! Everything will be rendered on demand!
#   +2.2 Keys were removed true/false => nitro_partial.db_cached_partials.where.not( nitro_partial.cache_keys.keys ).delete_all at rails start.
#   +2.3 New partial
#      а) true/false the new nitro_partial record would be added to DB at rails start if we use prerender or at first render otherwise
#         all prerendering only in rake!
#   +2.4 Partial changed.
#      +а) true/false remove all obsolete keys from DB at rails start
#   +2.5 Removing partial. all obsolete cache keys will be deleted at application start
#   -2.6 Prerender -> toggle
#     а) true -> false => do_nothing
#     б) false -> true => manually run rake :nitro_prerender to prerender those who don't exists.
#   2.7 partial naming changes.
#     a) it's possible to create rake rename_nitro_partial but right now you just rename your partial -
#        loose all rendered cache pieces and rerender them as if you create new one.
#        Also it's possible to change cache key mechanism generation and use not the file name, but file content
#        hash_key, then any renaming and moving of a file will not affect any cached values. Now it's not the point.
#   2.8 When expiration params changes При изменении параметров устаревания, проверяем в rake :expire_db_nitro_cache который можно в кронджобы вписать.
#       все кеши на соответствие новым правилам. Ненужное удаляем.

#                          ПРАВИЛА ИЗМНЕНИЯ КЕША, ЕСЛИ ЧТО_ТО ПОМЕНЯЛОСЬ (РУС)
# Главное правило: никакого пререндеринга на старте сервера иначе у деплоя развяжется пупок.
# На старте только: массовое удаление устаревшего, создание новых записей nitro_partial для новых паршиалов.
# Правила поведения кеша при изменениях ( поведение зависит от значения prerender - true|false)
# + 1 При изменении объекта:
#   а) prerender-true => after_commit -> render all variants
#   б) prerender-false => after_commit -> clear, view on demand -> render and mass save
# 2 при изменении параметров кеша:
#   +2.1 Добавились новые ключи.
#       true => рельсы стартуют без дополнительного пререндеринга, параллельно запускаем rake :nitro_prerender,
#       false => do nothing! Ключей не было, значений не было, все будет генериться по первому требованию
#   +2.2 Удалились ключи true/false => nitro_partial.db_cached_partials.where.not( nitro_partial.keys ).delete_all на старте приложения можно.
#       +б) Если уже сгенеренные значения не важны то можно просто переписать код, кеши для не найденных файлов будут удалены,
#         новые можно прерндернуть соответствующим рейком
#   -2.8 При изменении параметров устаревания, проверяем в rake :expire_db_nitro_cache который можно в кронджобы вписать.
#       все кеши на соответствие новым правилам. Ненужное удаляем.
#
#                                            PARTIAL PRERENDER
#
# Since pg_cache works as usual cache* also we can prerender only for part of keys and part of records, only most wanted.
# For example I have feed different for admin and user, but since admin can wait more and also looks at the feed not
# very often. So I can set for prerender locals: { role: [User] }, instead of locals: { role: [User, Admin] }
# and get twice less prerendered caches.
# Another example: we have a long history of payments but actual need is only for a last year for example,
# so we can set prerender scope with condition on :created_at column, and prerender only a last year records.
#
# *see section LIMITATIONS for more details on the possibilities of replacing usual feed cache with nitro
#
#                                           ЧАСТИЧНЫЙ ПРЕРЕНДЕРИНГ
# В силу того что nitro_cache может работать практически как обычный матрешный кеш* мы можем включить пререндеринг только для части
# ключей и части записей.
# Например у меня разное отображение ленты для админа и для пользователя. Админ пользуется лентой нечасто и в целом может
# подождать на полсекунды дольше. ТО в параметрах пререндеринга можно написать locals: { role: [User] }, вместо locals: { role: [User, Admin] }
# и пререндрить вполовину меньше вариантов для записи.
# Второй пример: мы ведем длинную историю оплат пользователей, но для работы бухов нужен последний квартал или там год
# мы можем выставить scope для пререндеринга по :created_at и пререрндерить только нужные записи.

#                                          EXPIRING
# Right now all cache get timestamp for the last access ( :viewed_at ) so it possible to control cache expiration on time basis
#
#                                         УСТАРЕВАНИЕ
# Сейчас все ключи хранят штамп времени последнего просмотра поэтому можно легко реализовать устаревающий кеш. например как рейк + крон-джоб
#
#                                CACHING ALGORITHMS ( STRAIGHT/REVERSE/ARRAY CACHING )
#
# Three types of caching collection mechanism are used: straight, 'reverse', array-elem
# straight and reverse used for relation objects! array-elem - instantinated array or elem
#
# straight (db_cache_collection_s) - similar to usual cache, we check does every elements already cached if so we just return aggregation result,
# if not - we just add +1 join on db_cahe_partial +1 select for cache_value as virtual attribute
# and then render element if cache_value.nil? otherwise use cache_value

#'reverse' (db_cache_collection_r) - is not similar to usual cache algorithms it used 'reversed' logic: we create special SQL-query only for non-cached
# elements, render them, and then we use aggregation on a given collection. This special SQL-query use all includes, joins, select which was in original
# query so we successfully escaping N+1 problems same way as usual cache did.
# This approach gives us more speed even on whole noncached collection. How it possible? I think this happens because we are
# escaping the delay between cache-service and rails app

# array-elem (db_cache_array) - this is method used only with prerender: true for changed record.
# DON'T USE IT ELSEWHERE!! If you have complex hierarchy of models and don't include them on update action of your controller
# it may give you N+1 problem internally.
#
#                               ВАРИАНТЫ КЕШИРОВАНИЯ ( STRAIGHT/REVERSE/ARRAY CACHING )
#
# Прямой и реверсивный ( straight and reverse ) используются только для relation объектов. ARRAY CACHING используется только если prerender: true
# для измененного элемента.
#
# Прямое кеширование: мы классическим образом сначала проверяем что вся коллекция закеширована. да - запросом на с исолпьзованием str_agg собираем фид
# коллекции на уровне БД. нет - идем последовательно и рендерим, если нет кеша, или подставляем кеш, если он есть.
#
# Реверс кеширование: Мы делаем дополнительный специальный SQL-запрос, с учетом тех настроек инклюдов джойнов и селектов которые есть в
# полученном relation, но с условием что выбираются только элементы по которым нет кеша. прогоняем по ним рендеринг коллекции.
# и после этого проводим запрос на аггрегацию фида. Данный вариант кеширования оказался быстрее как прямого кеширования, так и обычной связки memcache + dali
# ( я думаю из-за того что нет постоянного сохранения по одной записи в кеш это все умножится на делей )
#
#                               STRAIGHT VS REVERSE VS CLASSIC POSSIBLE PROBLEMS
# 1. DB Sharding for reverse-cache. If we use db sharding reverse-cache may need additional tuning and testing since it's doing its job
#   in two steps. Straight-cache will work anyway.
# 2. Exotic cases for any pg_cache. If we render same collection twice with different partial inside one controller action ( it's quite unusual behaviour ),
#    than we may instatinate collection twice.

#                               STRAIGHT VS REVERSE VS CLASSIC ВЕРОЯТНЫЕ ПРОБЛЕМЫ
# 1. БД-шардинг при обратном кешировании. Если мы используем БД шардинг, то вариант реверс кеширования требует доработки, потому что мы должны спрашивать
#    аггрегацию сразу же после того как сделали апдейт, поэтому по идее это должно идти на мастер-шард.
# 2. Экзотические варинты многоразового рендеринга с разными паршиалами одной коллекции в одном методе контроллера. Тогда может быть многоразовая инстантинация
#    на первом рендеринге.


#                                 NitroPartial STRUCTURE AND SPECS
# 1   В БД паршиалы уникальны по относительным путям
# 2.0 Параметры специфические для паршиала ( сколько хранить записей и когда экспайрить, можно задавать прямо в рендер )
# 2.1 При загрузке мы все паршиалы из БД всасываем в хеш partials_cache = { path: Partial }, проверяем наличие файлов,
#     если какого-то нет - вычищаем БД от его записей.
# 3   Проверяем что хеши на контент файлов не поменялись, для всех которые поменялись - удаляем кеш-записи
# 4   При запросе объекта Partial по путю из partials_cache в случае отсутствия оного - он сначала заправшивается в БД
#     ( это случай когда он параллельно был создан в соседнем процессе ) и если такого нет создается новый.
#
#                                   WORKING WITH LIMITS
#
# Общие лимиты можно устанавливать через конфиг на всех и на отдельные паршиалы следить
# за переполнением можно в кронджобах

#todo Есть проблема с кешированием паршиалов содержащих "устаревающий" контент,
# например ссылки устаревающие. Соответственно можно подумать над ее решением: Cron job которая занимается только тем,
# что чистит или перекеширует кеш таких элементов.
# Потом можно решить проблему немножечко по другому в ряде случаев, например, вместо прямой ссылки на скачивание,
# кешируется косвенная, или же идет дозапросы на сервер за обновленными данными, а структура закеширована.


#  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!FOR TESTING PURPOSE:
# Для целей тестирования достаточно переопределить ф-ию аггрегации и можно тестировать на sqlite :memory, т.е. в принципе замокать ее в спеках,
# остальное должно работать везде. + замокать cashe_keys возможно придется также ( если не сработает: https://sqlite.org/json1.html )
#
#   +2.3 Добавился partial
#      а) true/false на старте рельсов добавится новая запись в таблицу partials автоматом, НО генерации
#         не произойдет, вся генерация только в rake :nitro_prerender, иначе сервак на деплое прифигеет!!
#   +2.4 Partial поменялся.
#      +а) true/false удалит старые значения из БД
#      -б) пререндер только в rake :nitro_prerender!
#   +2.5 Удаление partial. проверка идет от БД, если в загруженном приложении нет раскладки по паршиалу то БД вычистится на старте приложения
#   -2.6 Prerender -> toggle
#     а) true -> false => do_nothing
#     б) false -> true => rake :nitro_prerender догенерит те кусочки которых нет
#   2.7 Изменение имени паршиала.
#       а) Если не хочется все перегенерировать, то во избежание косяков связанных с одновременно работающиими версиями, нужно
#         залить версию в которой присутствуют оба файла! И одновременно можно в отдельном рейке rake :rename_partials name1 name2 переименовать все ключи
require 'active_record'
require 'active_record/version'
require 'active_support/core_ext/module'

require 'rails/engine'
require 'nitro_pg_cache/engine'

require 'nitro_pg_cache/model_ext'
require 'nitro_pg_cache/viewer_ext'
require 'nitro_pg_cache/acts_as_nitro_cacheable'

ActiveSupport.on_load(:active_record) do
  extend NitroPgCache::NitroCacheable
end

ActiveSupport.on_load(:action_view) do
  include NitroPgCache::ViewerExt
end

class Hash
  # little lazy hackery, retrieve_cache_key - private, so technically it's wrong, but why the heck it's private?
  # retrieve_cache_key doesn't respect order so I force key sorting
  def to_nitro_cache_key
    "#{self[:partial]}_#{ActiveSupport::Cache.send( :retrieve_cache_key, self[:cache_by] )}_#{ self[:locals] && self[:locals].keys.sort.map{|key| ActiveSupport::Cache.send( :retrieve_cache_key, self[:locals][key] ) }.join("_")}"
  end
end

require_dependency 'models/nitro_cache'
require_dependency 'models/nitro_partial'