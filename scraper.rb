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
    dl = link.ancestors('h4').first&.next_element
    electorate = nil
    party = nil

    if dl && dl.name == 'dl'
      dl.search('dt').each do |dt|
        case dt.inner_text.strip
        when 'For'
          # "For: Calwell, Victoria" — strip the state suffix for members, keep as-is for senators
          electorate = dt.next_element&.inner_text&.strip
        when 'Party'
          party = dt.next_element&.inner_text&.strip
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

      # Email is in the Connect section as a mailto: link
      email_link = profile_page.search('a[href^="mailto:"]').first
      email = email_link.attr(:href).sub('mailto:', '').strip if email_link

      # Website links appear under the "Websites" section
      # They're plain <a> tags that aren't mailto: and aren't aph.gov.au internal links
      profile_page.search('a[href]').each do |a|
        href = a.attr(:href)
        next if href.start_with?('mailto:', 'javascript:', '#', 'tel:')
        next if href.include?('aph.gov.au')
        next if href.include?('parlinfo.aph.gov.au')
        next if href.include?('parlwork.aph.gov.au')
        next if href.include?('facebook.com') || href.include?('twitter.com') || href.include?('x.com')

        # Pick up facebook/twitter separately
        if href.include?('facebook.com')
          facebook = href
        elsif href.include?('twitter.com') || href.include?('x.com')
          twitter = href
        elsif website.nil? && href.start_with?('http')
          website = href
        end
      end

      # Re-scan for social links explicitly
      profile_page.search('a[href]').each do |a|
        href = a.attr(:href)
        if href.include?('facebook.com') && facebook.nil?
          facebook = href
        elsif (href.include?('twitter.com') || href.include?('x.com')) && twitter.nil?
          twitter = href
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
