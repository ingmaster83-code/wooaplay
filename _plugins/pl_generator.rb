require 'json'

module Jekyll
  # 한글 조사 + 데이터 기반 문장 도우미
  module LeisureText
    module_function

    AMBIG = {}   # 여러 시도에 같은 이름이 있는 시군구(중구·북구 등)

    def clean_tail(s)
      s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')
    end

    def hangul_tail?(s)
      c = clean_tail(s)[-1]
      !c.nil? && c.ord >= 0xAC00 && c.ord <= 0xD7A3
    end

    def batchim?(s)
      c = clean_tail(s)[-1]
      return false if c.nil?
      o = c.ord
      return (o - 0xAC00) % 28 != 0 if o >= 0xAC00 && o <= 0xD7A3
      false
    end

    def josa(word, with_b, without_b)
      return "#{word}#{with_b}(#{without_b})" unless hangul_tail?(word)
      word.to_s + (batchim?(word) ? with_b : without_b)
    end

    def i_ga(w);   josa(w, '이', '가'); end
    def eun_neun(w); josa(w, '은', '는'); end
    def eul_reul(w); josa(w, '을', '를'); end

    def sg_name(do_short, sg)
      AMBIG[sg] ? "#{do_short} #{sg}" : sg
    end

    def stats(list, year)
      dated = list.select { |i| i['permit'].to_s =~ /\A(19[5-9]\d|20\d\d)/ }
      oldest = dated.min_by { |i| [i['permit'], i['slug']] }
      {
        'n' => list.size,
        'tel' => list.count { |i| i['tel'].to_s != '' },
        'oldest' => oldest,
        'recent' => dated.count { |i| i['permit'][0, 4].to_i >= year - 3 }
      }
    end

    def top_dongs(list, k = 3)
      list.reject { |i| i['dong'] == '기타' }.group_by { |i| i['dong'] }
          .sort_by { |d, l| [-l.size, d] }.first(k).map { |d, _| d }
    end

    def dong_label(d)
      d == '기타' ? '기타 지역' : d
    end

    # 목록 요약 문장 (허브 페이지 본문 + 메타 설명 재료)
    def list_summary(scope, cat_label, st, year, dongs)
      s = +"#{scope}에는 영업 중인 #{cat_label} #{st['n']}곳이 등록되어 있습니다."
      s << " #{dongs.join('·')} 일대에 많습니다." if dongs.size >= 2
      s << " 이 중 전화번호가 공공데이터에 등록된 곳은 #{st['tel']}곳입니다."
      if st['oldest']
        o = st['oldest']
        s << " 가장 오래된 곳은 #{o['permit'][0, 4]}년에 인허가를 받은 #{o['facilityName']}(#{dong_label(o['dong'])})이며,"
        s << " 최근 3년(#{year - 3}년 이후) 새로 인허가를 받은 곳은 #{st['recent']}곳입니다."
      end
      s
    end
  end

  class LeisurePageGenerator < Generator
    safe true
    priority :normal

    CAP = 300
    CAT_DONG_MIN = 2
    NEAR_COUNT = 6

    CAT_ORDER = %w[노래방 코인노래방 영화관 공연장].freeze

    CAT_META = {
      '노래방' => {
        'law' => '등록', 'about' => '노래방은 「음악산업진흥에 관한 법률」에 따라 시·군·구청에 등록한 노래연습장업입니다. 노래방실 수와 청소년실 운영 여부는 업장마다 다릅니다.',
        'tips' => ['청소년 이용 가능 시간과 청소년실 운영 여부를 확인하세요.', '시간제인지 곡당 요금인지, 인원 추가 요금이 있는지 물어보세요.', '단체 예약·대관이 가능한지 미리 문의하세요.']
      },
      '코인노래방' => {
        'law' => '등록', 'about' => '코인노래방은 상호에 \'코인\'이 들어간 노래연습장으로, 곡 단위로 결제하는 소형 노래방이 많습니다. 법적으로는 일반 노래연습장업(등록) 업소입니다.',
        'tips' => ['곡당 요금인지 시간당 요금인지 결제 방식을 확인하세요.', '방 크기와 이용 가능 인원을 확인하세요.', '결제 수단(현금·카드·모바일)을 미리 확인하세요.']
      },
      '영화관' => {
        'law' => '등록', 'about' => '영화관(영화상영관)은 「영화 및 비디오물의 진흥에 관한 법률」에 따라 등록한 영화상영업 시설입니다. 이 목록은 같은 건물의 상영관 인허가를 한 곳으로 묶은 것입니다.',
        'tips' => ['상영 시간표와 예매는 각 영화관의 앱·홈페이지에서 확인하세요.', '독립·예술영화관은 상영 편수가 적어 사전 확인이 필요합니다.', '주차·할인 혜택은 건물(쇼핑몰) 정책에 따라 다릅니다.']
      },
      '공연장' => {
        'law' => '등록', 'about' => '공연장은 「공연법」에 따라 등록한 공연 시설입니다. 극장·소극장 등이 포함되며 공연 일정은 별도로 확인해야 합니다.',
        'tips' => ['공연 일정과 예매는 각 공연장·예매처에서 확인하세요.', '소극장은 좌석 수가 적어 사전 예매가 필요한 경우가 많습니다.', '주차 가능 여부를 미리 확인하세요.']
      }
    }.freeze

    def generate(site)
      items = []
      Dir.glob(File.join(site.source, '_rawdata', 'pl_*.json')).sort.each { |p| items.concat(load_json(p)) }
      return if items.empty?
      year = Time.now.getlocal('+09:00').year
      LeisureText::AMBIG.clear
      items.group_by { |i| i['sigungu'] }.each { |sg, l| LeisureText::AMBIG[sg] = true if l.map { |i| i['doShort'] }.uniq.size > 1 }
      cat_info = {}   # cat => {slug,label,icon}
      items.each { |i| cat_info[i['cat']] ||= { 'cat' => i['cat'], 'slug' => i['catSlug'], 'label' => i['catLabel'], 'icon' => i['catIcon'] } }
      cats_ordered = CAT_ORDER.select { |c| cat_info[c] }

      counts = { dong: 0, sg: 0, cat_sg: 0, cat_dong: 0, place: 0 }
      combo_list = []

      by_do = items.group_by { |i| i['doShort'] }
      by_do.each do |do_short, d_items|
        by_sg = d_items.group_by { |i| i['sigungu'] }
        site.pages << DoPage.new(site, do_short, d_items, by_sg, cat_info, cats_ordered, year)

        by_sg.each do |sg, sg_items|
          sg_slug = sg_items.first['sgSlug']
          by_dong = sg_items.group_by { |i| i['dong'] }
          sg_cat = sg_items.group_by { |i| i['cat'] }
          site.pages << SigunguPage.new(site, do_short, sg, sg_slug, sg_items, by_dong, sg_cat, cat_info, cats_ordered, year)
          counts[:sg] += 1

          sg_cat.each do |cat, l|
            site.pages << CatSgPage.new(site, cat_info[cat], cat, do_short, sg, sg_slug, l, year)
            counts[:cat_sg] += 1
            combo_list << { 'url' => "/cat/#{cat_info[cat]['slug']}/#{do_short}/#{sg_slug}/", 'label' => "#{sg} #{cat_info[cat]['label']}", 'do' => do_short, 'count' => l.size }
          end

          by_dong.each do |dong, list|
            site.pages << DongPage.new(site, do_short, sg, sg_slug, dong, list, cat_info, cats_ordered, year)
            counts[:dong] += 1
            dong_cat = list.group_by { |i| i['cat'] }

            dong_cat.each do |cat, l|
              next if dong == '기타' || l.size < CAT_DONG_MIN
              site.pages << CatDongPage.new(site, cat_info[cat], cat, do_short, sg, sg_slug, dong, l, year)
              counts[:cat_dong] += 1
            end

            dong_cat.each do |cat, l|
              sorted = l.sort_by { |i| i['catDongRank'] }
              name_cnt = Hash.new(0)
              sorted.each { |x| name_cnt[x['facilityName']] += 1 }
              sorted.each { |x| x['dupName'] = name_cnt[x['facilityName']] > 1 }
              sg_pool = sg_cat[cat]
              sorted.each_with_index do |c, idx|
                near = []
                (1..[NEAR_COUNT, sorted.size - 1].min).each { |k| near << sorted[(idx + k) % sorted.size] } if sorted.size > 1
                if near.size < NEAR_COUNT
                  extra = sg_pool.reject { |x| x['dong'] == dong }.sort_by { |x| [x['dong'], x['slug']] }
                  start = extra.empty? ? 0 : (c['slug'].hash.abs % extra.size)
                  (0...[NEAR_COUNT - near.size, extra.size].min).each { |k| near << extra[(start + k) % extra.size] }
                end
                site.pages << PlacePage.new(site, c, cat_info[cat], near, year)
                counts[:place] += 1
              end
            end
          end
        end

        d_items.group_by { |i| i['cat'] }.each do |cat, l|
          site.pages << CatDoPage.new(site, cat_info[cat], cat, do_short, l, year)
        end
      end

      cats_ordered.each do |cat|
        l = items.select { |i| i['cat'] == cat }
        site.pages << CatPage.new(site, cat_info[cat], cat, l, year)
      end
      site.pages << CatIndexPage.new(site, cats_ordered.map { |c| cat_info[c].merge('count' => items.count { |i| i['cat'] == c }) })

      site.data['pl_stats'] = {
        'total' => items.size,
        'total_fmt' => items.size.to_s.reverse.scan(/\d{1,3}/).join(',').reverse,
        'cats' => cats_ordered.map { |c| n = items.count { |i| i['cat'] == c }; cat_info[c].merge('count' => n, 'count_fmt' => n.to_s.reverse.scan(/\d{1,3}/).join(',').reverse) },
        'do_counts' => by_do.map { |d, l| { 'name' => d, 'count' => l.size } },
        'top_combos' => combo_list.sort_by { |h| [-h['count'], h['url']] }.first(30),
        'year' => year
      }

      Jekyll.logger.info 'LeisureGenerator:', "시군구 #{counts[:sg]} / 동 #{counts[:dong]} / 종류×시군구 #{counts[:cat_sg]} / 종류×동 #{counts[:cat_dong]} / 시설 #{counts[:place]}"
    end

    private

    def load_json(path)
      JSON.parse(File.read(path, encoding: 'utf-8'))
    rescue => e
      Jekyll.logger.warn 'LeisureGenerator:', "#{path} 로드 실패: #{e.message}"
      []
    end
  end

  class LeisureBasePage < Page
    def setup(site, dir, layout)
      @site = site
      @base = site.source
      @dir = dir
      @name = 'index.html'
      process(@name)
      read_yaml(File.join(@base, '_layouts'), "#{layout}.html")
      data['layout'] = layout
    end

    def seo(title, desc)
      data['title'] = title
      data['description'] = desc[0, 155]
    end

    def make_faq(pairs)
      data['faq'] = pairs.map { |q, a| { 'q' => q, 'a' => a } }
    end

    def meta(cat)
      LeisurePageGenerator::CAT_META[cat] || {}
    end

    def count_rows(list, key)
      list.group_by { |i| i[key] }.map { |k, l| [k, l.size] }
    end
  end

  class DoPage < LeisureBasePage
    def initialize(site, do_short, items, by_sg, cat_info, cats_ordered, year)
      setup(site, "region/#{do_short}", 'do')
      cat_counts = items.group_by { |i| i['cat'] }
      data['doShort'] = do_short
      data['totalCount'] = items.size
      data['catList'] = cats_ordered.select { |c| cat_counts[c] }.map { |c| cat_info[c].merge('count' => cat_counts[c].size) }
      data['sigunguList'] = by_sg.map { |sg, l| { 'name' => sg, 'slug' => l.first['sgSlug'], 'count' => l.size } }.sort_by { |h| -h['count'] }
      top = data['catList'].first(3).map { |c| c['label'] }.join('·')
      seo("#{do_short} 노래방·코인노래방·영화관 #{items.size}곳 - 시군구별 놀거리 시설",
          "#{do_short}의 놀거리 시설 #{items.size}곳(#{top} 등)을 시군구·동별로 확인하세요. 주소와 전화번호, 인허가 정보를 공공데이터로 안내합니다.")
    end
  end

  class SigunguPage < LeisureBasePage
    def initialize(site, do_short, sg, sg_slug, items, by_dong, sg_cat, cat_info, cats_ordered, year)
      setup(site, "region/#{do_short}/#{sg_slug}", 'sigungu')
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = sg_slug
      data['totalCount'] = items.size
      data['catList'] = cats_ordered.select { |c| sg_cat[c] }.map { |c| cat_info[c].merge('count' => sg_cat[c].size) }
      data['dongList'] = by_dong.map { |dg, l| { 'name' => dg, 'label' => LeisureText.dong_label(dg), 'count' => l.size } }
                                .sort_by { |h| h['name'] == '기타' ? [1, 0] : [0, -h['count']] }
      top = data['catList'].first(3).map { |c| "#{c['label']} #{c['count']}곳" }.join(', ')
      data['summary'] = "#{do_short} #{sg}에는 영업 중인 놀거리 시설이 #{items.size}곳 등록되어 있습니다(#{top}). 동·읍·면 또는 종류을 선택해 주소와 전화번호를 확인하세요."
      seo("#{LeisureText.sg_name(do_short, sg)} 노래방·코인노래방·영화관 #{items.size}곳",
          "#{do_short} #{sg}의 노래방·코인노래방·영화관·공연장 등 놀거리 시설 #{items.size}곳을 동별·종류별로 찾아보세요. 주소·전화번호·인허가 정보 제공.")
    end
  end

  class DongPage < LeisureBasePage
    def initialize(site, do_short, sg, sg_slug, dong, list, cat_info, cats_ordered, year)
      setup(site, "region/#{do_short}/#{sg_slug}/#{dong}", 'dong')
      label = LeisureText.dong_label(dong)
      by_cat = list.group_by { |i| i['cat'] }
      groups = cats_ordered.select { |c| by_cat[c] }.map do |c|
        l = by_cat[c].sort_by { |i| i['facilityName'] }
        cat_info[c].merge('count' => l.size, 'items' => l.first(LeisurePageGenerator::CAP),
                          'hubLink' => (dong != '기타' && l.size >= LeisurePageGenerator::CAT_DONG_MIN))
      end
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = sg_slug
      data['dong'] = dong
      data['dongLabel'] = label
      data['sgLabel'] = LeisureText.sg_name(do_short, sg)
      data['totalCount'] = list.size
      data['groups'] = groups
      brief = groups.first(3).map { |g| "#{g['label']} #{g['count']}곳" }.join(', ')
      data['summary'] = "#{do_short} #{sg} #{label}에는 영업 중인 놀거리 시설이 #{list.size}곳 등록되어 있습니다(#{brief}). 종류별로 이름·주소·전화번호를 확인하세요."
      names = groups.first(3).map { |g| g['label'] }.join('·')
      seo("#{LeisureText.sg_name(do_short, sg)} #{label} #{names} #{list.size}곳",
          "#{do_short} #{sg} #{label}의 #{names} 등 놀거리 시설 #{list.size}곳. 시설별 주소·전화번호·인허가일을 공공데이터로 확인하세요.")
      pairs = []
      pairs << ["#{sg} #{label}에 놀거리 시설이 몇 곳 있나요?", "공공데이터(영업/정상 상태) 기준 #{do_short} #{sg} #{label}에는 #{list.size}곳이 있고, #{groups.map { |g| "#{g['label']} #{g['count']}곳" }.join(', ')}입니다."]
      big = groups.max_by { |g| g['count'] }
      pairs << ["#{label}에서 가장 많은 시설은 무엇인가요?", "#{label}에서는 #{big['label']}이(가) #{big['count']}곳으로 가장 많습니다."] if big
      pairs << ["운영 시간과 이용 요금은 어디서 확인하나요?", "이 사이트는 공공 인허가 데이터에 있는 주소·전화번호·인허가일 정보를 제공합니다. 요금과 운영 시간은 업장마다 다르고 바뀔 수 있으니 방문 전에 시설에 직접 문의하세요."]
      make_faq(pairs)
    end
  end

  class CatListBase < LeisureBasePage
    def fill_common(ci, cat, do_short, sg, sg_slug, dong, list, year, scope)
      m = meta(cat)
      st = LeisureText.stats(list, year)
      cl = ci['label']
      data['cat'] = cat
      data['catSlug'] = ci['slug']
      data['catLabel'] = cl
      data['catIcon'] = ci['icon']
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = sg_slug
      data['dong'] = dong
      data['dongLabel'] = dong ? LeisureText.dong_label(dong) : nil
      data['sgLabel'] = LeisureText.sg_name(do_short, sg)
      data['scope'] = scope
      data['totalCount'] = list.size
      data['truncated'] = list.size > LeisurePageGenerator::CAP
      data['items'] = list.sort_by { |i| [i['dong'], i['facilityName']] }.first(LeisurePageGenerator::CAP)
      data['about'] = m['about']
      data['tips'] = m['tips']
      data['summary'] = LeisureText.list_summary(scope, cl, st, year, LeisureText.top_dongs(list))
      [st, cl]
    end

    def list_faq(scope, cl, st, list)
      pairs = []
      pairs << ["#{LeisureText.eun_neun("#{scope} #{cl}")} 몇 곳 있나요?", "공공데이터(영업/정상 상태) 기준 #{scope}에는 #{cl} #{st['n']}곳이 있습니다. 전화번호가 등록된 곳은 #{st['tel']}곳입니다."]
      if st['oldest']
        o = st['oldest']
        pairs << ["#{scope}에서 가장 오래된 #{LeisureText.eun_neun(cl)} 어디인가요?", "#{o['facilityName']}(#{LeisureText.dong_label(o['dong'])})이 #{o['permit']}에 인허가를 받아 가장 오래됐습니다. 최근 3년 안에 새로 인허가를 받은 곳은 #{st['recent']}곳입니다."]
      end
      pairs << ["#{cl} 이용 전 무엇을 확인해야 하나요?", (meta(list.first['cat'])['tips'] || []).join(' ')] unless (meta(list.first['cat'])['tips'] || []).empty?
      pairs << ["#{cl} 요금과 운영 시간은 어디서 확인하나요?", "이 사이트는 공공 인허가 데이터의 주소·전화번호·인허가일을 제공합니다. 요금과 운영 시간은 업장마다 달라 방문 전 직접 문의가 필요합니다."]
      pairs
    end
  end

  class CatDongPage < CatListBase
    def initialize(site, ci, cat, do_short, sg, sg_slug, dong, list, year)
      setup(site, "cat/#{ci['slug']}/#{do_short}/#{sg_slug}/#{dong}", 'cat_list')
      scope = "#{do_short} #{sg} #{dong}"
      st, cl = fill_common(ci, cat, do_short, sg, sg_slug, dong, list, year, scope)
      data['level'] = 'dong'
      seo("#{LeisureText.sg_name(do_short, sg)} #{dong} #{cl} #{list.size}곳 - 주소·전화번호",
          "#{do_short} #{sg} #{dong}의 #{cl} #{list.size}곳 목록. 시설별 주소, 전화번호, 인허가일을 공공데이터 기준으로 안내합니다.")
      make_faq(list_faq(scope, cl, st, list))
    end
  end

  class CatSgPage < CatListBase
    def initialize(site, ci, cat, do_short, sg, sg_slug, list, year)
      setup(site, "cat/#{ci['slug']}/#{do_short}/#{sg_slug}", 'cat_list')
      scope = "#{do_short} #{sg}"
      st, cl = fill_common(ci, cat, do_short, sg, sg_slug, nil, list, year, scope)
      data['level'] = 'sg'
      dongs = list.group_by { |i| i['dong'] }.map { |d, l| { 'name' => d, 'label' => LeisureText.dong_label(d), 'count' => l.size, 'hub' => (d != '기타' && l.size >= LeisurePageGenerator::CAT_DONG_MIN) } }
                  .sort_by { |h| h['name'] == '기타' ? [1, 0, ''] : [0, -h['count'], h['name']] }
      data['dongList'] = dongs
      seo("#{LeisureText.sg_name(do_short, sg)} #{cl} #{list.size}곳 - 동별 위치·전화번호",
          "#{do_short} #{sg}의 #{cl} #{list.size}곳을 동별로 확인하세요. 시설 이름·주소·전화번호·인허가일을 공공데이터 기준으로 안내합니다.")
      make_faq(list_faq(scope, cl, st, list))
    end
  end

  class CatDoPage < CatListBase
    def initialize(site, ci, cat, do_short, list, year)
      setup(site, "cat/#{ci['slug']}/#{do_short}", 'cat_do')
      m = meta(cat)
      st = LeisureText.stats(list, year)
      cl = ci['label']
      data['cat'] = cat
      data['catSlug'] = ci['slug']
      data['catLabel'] = cl
      data['catIcon'] = ci['icon']
      data['doShort'] = do_short
      data['totalCount'] = list.size
      data['about'] = m['about']
      data['tips'] = m['tips']
      data['sigunguList'] = list.group_by { |i| i['sigungu'] }.map { |sg, l| { 'name' => sg, 'slug' => l.first['sgSlug'], 'count' => l.size } }.sort_by { |h| [-h['count'], h['name']] }
      data['summary'] = LeisureText.list_summary(do_short, cl, st, year, data['sigunguList'].first(3).map { |h| h['name'] })
      seo("#{do_short} #{cl} #{list.size}곳 - 시군구별 목록",
          "#{do_short}의 #{cl} #{list.size}곳을 시군구별로 찾아보세요. 시설별 주소·전화번호·인허가일을 공공데이터로 안내합니다.")
      make_faq(list_faq(do_short, cl, st, list))
    end
  end

  class CatPage < CatListBase
    def initialize(site, ci, cat, list, year)
      setup(site, "cat/#{ci['slug']}", 'cat')
      m = meta(cat)
      cl = ci['label']
      data['cat'] = cat
      data['catSlug'] = ci['slug']
      data['catLabel'] = cl
      data['catIcon'] = ci['icon']
      data['totalCount'] = list.size
      data['about'] = m['about']
      data['tips'] = m['tips']
      data['doList'] = list.group_by { |i| i['doShort'] }.map { |d, l| { 'name' => d, 'count' => l.size } }.sort_by { |h| -h['count'] }
      st = LeisureText.stats(list, year)
      data['summary'] = "전국에 영업 중인 #{LeisureText.eun_neun(cl)} 공공데이터 기준 #{list.size}곳입니다. 시도를 선택해 시군구·동별 #{LeisureText.eul_reul(cl)} 찾아보세요."
      seo("전국 #{cl} #{list.size.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}곳 - 지역별 위치·전화번호",
          "전국 #{cl} #{list.size}곳을 시도·시군구·동별로 찾아보세요. 주소와 전화번호, 인허가 정보를 공공데이터로 안내합니다.")
      make_faq(list_faq('전국', cl, st, list))
    end
  end

  class CatIndexPage < LeisureBasePage
    def initialize(site, cat_rows)
      setup(site, 'cat', 'cat_index')
      data['catList'] = cat_rows
      seo('종류별 놀거리 시설 찾기 - 노래방·코인노래방·영화관·공연장', '노래방·코인노래방·영화관 등 종류별로 전국 놀거리 시설을 찾아보세요.')
    end
  end

  class PlacePage < LeisureBasePage
    def initialize(site, c, ci, near, year)
      setup(site, "place/#{c['slug']}", 'place')
      data.merge!(c)
      cat = c['cat']
      m = meta(cat)
      cl = c['catLabel']
      dl = LeisureText.dong_label(c['dong'])
      dong_part = c['dong'] == '기타' ? '' : " #{c['dong']}"
      addr = c['road'].to_s != '' ? c['road'] : c['lot']
      data['addr'] = addr
      data['dongLabel'] = dl
      data['near'] = near.map { |x| { 'slug' => x['slug'], 'name' => x['facilityName'], 'dong' => x['dong'], 'catLabel' => x['catLabel'] } }
      data['about'] = m['about']
      data['tips'] = m['tips']
      data['law'] = m['law']
      py = c['permit'].to_s[0, 4].to_i
      data['permitYear'] = py > 1950 ? py : nil

      n = c['catDongCount']
      r = c['catDongRank']
      name = c['facilityName']
      data['nameEun'] = LeisureText.eun_neun(name)
      data['catI'] = LeisureText.i_ga(cl)
      data['catEun'] = LeisureText.eun_neun(cl)
      age = py > 1950 ? year - py : nil
      data['sinceYears'] = age
      s = +"#{LeisureText.eun_neun(name)} #{c['doShort']} #{c['sigungu']}#{dong_part}에 있는 #{cl}입니다."
      if py > 1950
        s << (age <= 0 ? " #{c['permit']}에 새로 인허가를 받은 신규 시설이고," : " #{c['permit']}에 인허가를 받아 #{age}년째 운영 기록이 있고,")
        if n > 1
          rank_txt = r == 1 ? "가장 먼저 인허가를 받은 곳입니다." : (r == n ? "가장 최근에 인허가를 받은 곳입니다." : "인허가가 #{r}번째로 오래됐습니다.")
          s << " #{dl}의 #{cl} #{n}곳 중 #{rank_txt}"
        else
          s << " #{dl}에 등록된 유일한 #{cl}입니다."
        end
      else
        s << (n > 1 ? " #{dl}에는 #{LeisureText.i_ga(cl)} 모두 #{n}곳 있습니다." : " #{dl}에 등록된 유일한 #{cl}입니다.")
      end
      data['summary'] = s

      tel_txt = c['tel'].to_s != '' ? c['tel'] : nil
      road_hint = c['dupName'] ? " (#{addr.sub(/\s*\(.*\z/, '').split(' ').last(2).join(' ')}#{c['subtype'].to_s != '' ? ', ' + c['subtype'] : ''})" : ''
      seo("#{name}#{road_hint} - #{LeisureText.sg_name(c['doShort'], c['sigungu'])}#{dong_part} #{cl} 주소·전화번호",
          "#{c['doShort']} #{c['sigungu']}#{dong_part} #{cl} #{name}. 주소 #{addr}#{tel_txt ? ", 전화 #{tel_txt}" : ''}, 인허가 #{c['permit'].to_s != '' ? c['permit'] : '정보 없음'}. 공공데이터 기준 영업 중 시설.")

      pairs = []
      pairs << ["#{LeisureText.eun_neun(name)} 어디에 있나요?","주소는 #{addr}입니다. #{c['doShort']} #{c['sigungu']}#{dong_part}에 위치해 있으며, 카카오맵으로 정확한 위치를 확인할 수 있습니다."]
      pairs << ["#{name} 전화번호는 무엇인가요?", tel_txt ? "공공데이터에 등록된 전화번호는 #{tel_txt}입니다. 운영 시간과 요금은 전화로 먼저 확인하세요." : "공공데이터에 전화번호가 등록되어 있지 않습니다. 카카오맵 등 지도 서비스에서 업장 정보를 확인하거나 현장에서 문의하세요."]
      if py > 1950
        pairs << ["#{LeisureText.eun_neun(name)} 언제 인허가를 받았나요?", "#{c['permit']}에 인허가를 받은 것으로 공공데이터에 등록되어 있으며, 정보 최종 수정일은 #{c['upd'].to_s != '' ? c['upd'] : '확인 불가'}입니다."]
      end
      pairs << ["#{dl}에는 다른 #{LeisureText.i_ga(cl)} 있나요?", n > 1 ? "#{dl}에는 #{LeisureText.i_ga(cl)} 모두 #{n}곳 있습니다. 아래 '#{c['sigungu']} 다른 #{cl}' 목록에서 확인하세요." : "공공데이터 기준 #{dl}에서 영업 중인 #{LeisureText.eun_neun(cl)} 이곳뿐입니다. 시군구 목록에서 인근 동의 시설을 확인하세요."]
      make_faq(pairs)
    end
  end

  # 사이트맵: 5만 건 한도 때문에 40,000건씩 분할 + 인덱스
  class LeisureSitemapGenerator < Generator
    safe true
    priority :lowest
    CHUNK = 40_000

    def generate(site)
      urls = site.pages.reject { |p| p.url.to_s.end_with?('.json', '.xml', '.txt', '.js', '.css') || p.url.to_s == '/404.html' || p.data['sitemap'] == false }
                       .map { |p| p.url }.uniq
      base = site.config['url'].to_s
      chunks = urls.each_slice(CHUNK).to_a
      chunks.each_with_index do |c, idx|
        body = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        c.each { |u| body << "  <url><loc>#{base}#{u}</loc></url>\n" }
        body << "</urlset>\n"
        site.pages << raw_page(site, "sitemap-#{idx + 1}.xml", body)
      end
      index = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
      chunks.each_index { |idx| index << "  <sitemap><loc>#{base}/sitemap-#{idx + 1}.xml</loc></sitemap>\n" }
      index << "</sitemapindex>\n"
      site.pages << raw_page(site, 'sitemap.xml', index)
      Jekyll.logger.info 'LeisureSitemap:', "#{urls.size}개 URL → #{chunks.size}개 사이트맵"
    end

    private

    def raw_page(site, name, content)
      pg = PageWithoutAFile.new(site, site.source, '', name)
      pg.content = content
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      pg
    end
  end
end
