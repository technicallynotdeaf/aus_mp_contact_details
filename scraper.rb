require 'scraperwiki'
require 'mechanize'

BASE_URL = 'https://www.aph.gov.au'
# 96 is the maximum page size the APH search supports
PAGE_SIZE = 96

def save_results_from_page(page, house)
  # Results are now <h4> + <dl> blocks, not <li> inside .search-filter-results
  page.search('h4 a[href*="MPID"]').each do |link|
    aph_id = link.attr(:href).match(/MPID\=(.*)/)[1]
    full_name = link.inner_text.strip

    # Note: avoid &. safe navigation operator — Morph runs Ruby 1.9 which doesn't support it
    h4 = link.ancestors('h4').first
    dl = h4 ? h4.next_element : nil
    electorate = nil
    party = nil

    if dl && dl.name == 'dl'
      dl.search('dt').each do |dt|
        next_el = dt.next_element
        case dt.inner_text.strip
        when 'For'
          electorate = next_el ? next_el.inner_text.strip : nil
        when 'Party'
          party = next_el ? next_el.inner_text.strip : nil
        end
      end
    end

    profile_page_url = "#{BASE_URL}/Senators_and_Members/Parliamentarian?MPID=#{aph_id}"

    email = nil
    facebook = nil
    twitter = nil
    website = nil

    begin
      profile_page = @agent.get profile_page_url

      profile_page.search('a[href]').each do |a|
        href = a.attr(:href)
        next if href.nil?
        if href.start_with?('mailto:')
          email ||= href.sub('mailto:', '').strip
        elsif href.include?('facebook.com') && facebook.nil?
          facebook = href
        elsif (href.include?('twitter.com') || href.include?('x.com')) && twitter.nil?
          twitter = href
        elsif website.nil? && href.start_with?('http') &&
              !href.include?('aph.gov.au') && !href.include?('surveymonkey.com')
          website = href
        end
      end
    rescue => e
      puts "  Warning: could not fetch profile for #{full_name}: #{e.message}"
    end

    photo_url = "#{BASE_URL}/api/parliamentarian/#{aph_id}/image"

    record = {
      house: house.to_s,
      aph_id: aph_id,
      full_name: full_name,
      electorate: electorate,
      party: party,
      profile_page: profile_page_url,
      contact_page: "#{BASE_URL}/Senators_and_Members/Contact_Senator_or_Member?MPID=#{aph_id}",
      photo_url: photo_url,
      email: email,
      facebook: facebook,
      twitter: twitter,
      website: website
    }

    puts "Saving #{record[:full_name]}"
    ScraperWiki::save_sqlite [:aph_id], record
  end
end

def scrape_chamber(chamber_param, house)
  search_url = "#{BASE_URL}/Senators_and_Members/Parliamentarian_Search_Results"
  page_num = 1

  loop do
    # We build pagination URLs manually rather than following the "Next" link,
    # because the "Next" link drops the chamber filter (mem=1/sen=1) from the
    # query string, causing page 2+ to return a 404.
    url = "#{search_url}?page=#{page_num}&q=&#{chamber_param}&par=-1&gen=0&ps=#{PAGE_SIZE}&st=1"
    puts "Fetching page #{page_num} (#{house})..."
    page = @agent.get url

    results = page.search('h4 a[href*="MPID"]')
    break if results.empty?

    save_results_from_page(page, house)

    # Stop if there's no "Next" link (we're on the last page)
    break unless page.link_with(:text => 'Next')

    page_num += 1
  end
end

@agent = Mechanize.new

puts "Saving results from Representatives pages"
scrape_chamber('mem=1', :representatives)

puts "Saving results from Senate pages"
scrape_chamber('sen=1', :senate)
