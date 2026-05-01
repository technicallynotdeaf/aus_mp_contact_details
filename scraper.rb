require 'scraperwiki'
require 'mechanize'

BASE_URL = 'https://www.aph.gov.au'

def save_results_from_page(page, house)
  # Results are now individual <section> or <h4>-headed blocks, not <li> in .search-filter-results.
  # Each result is an <h4> with an <a> linking to the profile, followed by a <dl> with details.
  page.search('h4 a[href*="MPID"]').each do |link|
    aph_id = link.attr(:href).match(/MPID\=(.*)/)[1]
    full_name = link.inner_text.strip

    # The <dl> immediately follows the <h4> parent
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

    # Fetch individual profile page for email and website
    email = nil
    facebook = nil
    twitter = nil
    website = nil

    begin
      profile_page = @agent.get profile_page_url

      # Scan all links for email, social, and personal website
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

    # Photo URL is now served from the API endpoint
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

@agent = Mechanize.new
# Use ps=0 to return all results on a single page, avoiding pagination entirely.
# The old pagination was broken because the "Next" link dropped mem=1/sen=1 from the query string.
search_url = "#{BASE_URL}/Senators_and_Members/Parliamentarian_Search_Results"

puts "Saving results from Representatives page"
page = @agent.get "#{search_url}?q=&mem=1&par=-1&gen=0&ps=0"
save_results_from_page(page, :representatives)

puts "Saving results from Senate page"
page = @agent.get "#{search_url}?q=&sen=1&par=-1&gen=0&ps=0"
save_results_from_page(page, :senate)
