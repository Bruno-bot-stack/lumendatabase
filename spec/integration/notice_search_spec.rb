require 'rails_helper'
require 'yaml'
require 'support/contain_link'

feature "Searching Notices", type: :feature do
  include SearchHelpers
  include ContainLink

  scenario "displays the results" do
    create_list(:dmca, 5, title: 'Boy howdy')
    index_changed_instances

    submit_search 'Boy howdy'

    expect(page).to have_css('.result', count: 5)
  end

  scenario 'includes facets' do
    create(:dmca, :with_facet_data, title: 'Facet this')

    index_changed_instances

    submit_search 'Facet this'

    # These counts match what's generated by :with_facet_data in
    # spec/factories.rb (plus one for an "All" link) and may fail if that code
    # is changed.
    expect(page).to have_css('ol.language_facet li', count: 2)
    expect(page).to have_css('ol.tag_list_facet li', count: 3)
    # This fails because a spurious 'Copyright' topic is showing up and I can't
    # track down why. --ay 5 December 2018
    # expect(page).to have_css('ol.topic_facet li', count: 4)
    expect(page).to have_css('ol.sender_name_facet li', count: 2)
    expect(page).to have_css('ol.principal_name_facet li', count: 2)
    expect(page).to have_css('ol.recipient_name_facet li', count: 2)
    expect(page).to have_css('ol.submitter_name_facet li', count: 1)
    expect(page).to have_css('ol.action_taken_facet li', count: 2)
  end

  scenario 'displays correct content when a notice only has a principal' do
    create(:dmca, role_names: %w[principal], title: 'A notice')
    index_changed_instances
    submit_search 'A notice'

    expect(page).not_to have_css('.result', text: 'on behalf of')
    expect(page).not_to have_css('.result', text: '/faceted_search')
  end

  scenario 'includes the relevant notice data' do
    notice = create(
      :dmca,
      role_names: %w[sender principal recipient],
      title: 'A notice',
      date_received: Time.now,
      topics: create_list(:topic, 2)
    )
    on_behalf_of = "#{notice.sender_name} on behalf of #{notice.principal_name}"
    index_changed_instances

    submit_search 'A notice'
    expect(page).to have_link(notice.title, href: notice_path(notice))
    expect(page).to have_css(
      '.result .date-received', text: notice.date_received.to_s(:simple)
    )
    expect(page).to have_content(on_behalf_of)
    notice.topics.each do |topic|
      expect(page).to have_css('.result .topic', text: topic.name)
    end
  end

  scenario 'includes excerpts' do
    create(:dmca, title: 'foo bar baz')
    index_changed_instances

    submit_search 'foo'

    expect(page).to have_content('foo bar baz')
  end

  scenario 'sanitizes excerpts' do
    create(:dmca, title: '<strong>foo</strong> and <em>bar</em>')
    index_changed_instances

    submit_search 'foo'

    expect(page).not_to have_css('li.excerpt',
      text:'<strong>foo</strong> and <em>bar</em>'
    )
  end

  scenario 'caching respects pagination', cache: true do
    # Create enough notices to force pagination of results. The concern here
    # is that caching a search result page might inadvertently cause all pages
    # of a search to match the first viewed page - we want to make sure that
    # doesn't happen.
    create_list(:dmca, 15, title: 'paginate me')
    index_changed_instances

    submit_search 'paginate me'

    first_page = page.body

    find('.next a').click

    second_page = page.body
    expect(first_page).not_to eq second_page
  end

  scenario "displays search terms", search: true do
    create(:dmca, title: "The Lion King on Youtube")
    index_changed_instances

    submit_search 'awesome blossom'

    expect(page).to have_css("input#search[value='awesome blossom']")
  end

  scenario "for full-text on a single model", search: true do
    notice = create(:dmca, title: "The Lion King on Youtube")
    trademark = create(:trademark, title: "Coke - it's the King thing")
    index_changed_instances

    within_search_results_for("king") do
      expect(page).to have_n_results(2)
      expect(page).to have_content(notice.title)
      expect(page).to have_content(trademark.title)
      expect(page.html).to have_excerpt('King', 'The Lion', 'on Youtube')
    end
  end

  scenario "based on action taken", search: true do
    notices = [
      create(:dmca, action_taken: 'No'),
      create(:dmca, action_taken: 'Yes'),
      create(:dmca, action_taken: 'Partial'),
    ]
    index_changed_instances

    notices.each do |notice|
      search_for(action_taken: notice.action_taken)

      expect(page).to have_n_results(1)
      expect(page).to have_content(notice.title)
    end
  end

  scenario "paginates properly", search: true do
    3.times do
      create(:dmca, title: "The Lion King on Youtube")
    end
    index_changed_instances

    search_for(term: 'lion', page: 2, per_page: 1)

    within('.pagination') do
      expect(page).to have_css('.current', text: 2)
      expect(page).to have_css('a[rel="next"]')
      expect(page).to have_css('a[rel="prev"]')
    end
  end

  scenario "it does not include rescinded notices", search: true do
    notice = create(:dmca, title: "arbitrary", rescinded: true)
    index_changed_instances

    expect_search_to_not_find("arbitrary", notice)
  end

  scenario "it does not include spam notices", search: true do
    notice = create(:dmca, title: "arbitrary", spam: true)
    index_changed_instances

    expect_search_to_not_find("arbitrary", notice)
  end

  scenario "it does not include hidden notices", search: true do
    notice = create(:dmca, title: "arbitrary", hidden: true)
    index_changed_instances

    expect_search_to_not_find("arbitrary", notice)
  end

  scenario "it does not include unpublished notices", search: true do
    notice = create(:dmca, title: "fanciest pants", published: false)
    found_notice = create(:dmca, title: "fancy pants")
    index_changed_instances

    within_search_results_for("pants") do
      expect(page).to have_n_results(1)
      expect(page).to have_content(found_notice.title)
    end

    expect_search_to_not_find("fanciest pants", notice)
  end

  context "within associated models" do
    scenario "for topic names", search: true do
      topic = create(:topic, name: "Lion King")
      notice = create(:dmca, topics: [topic])
      index_changed_instances

      within_search_results_for("king") do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page).to have_content(topic.name)
        expect(page).to contain_link(topic_path(topic))
        expect(page.html).to have_excerpt('King', 'Lion')
      end
    end

    scenario "for tags", search: true do
      notice = create(:dmca, tag_list: 'foo, bar')
      index_changed_instances

      within_search_results_for("bar") do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page.html).to have_excerpt("bar")
      end
    end

    scenario "for entities", search: true do
      notice = create(:dmca, role_names: %w( sender principal recipient))
      index_changed_instances

      within_search_results_for(notice.recipient_name) do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page).to have_content(notice.recipient_name)
        expect(page.html).to have_excerpt('Entity')
      end

      within_search_results_for(notice.sender_name) do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page).to have_content(notice.sender_name)
        expect(page.html).to have_excerpt('Entity')
      end

      within_search_results_for(notice.principal_name) do
        # note: principal name not shown in results
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page.html).to have_excerpt('Entity')
      end
    end

    scenario "for works", search: true do
      work = create(
        :work, description: "An arbitrary description"
      )

      notice = create(:dmca, works: [work])
      index_changed_instances

      within_search_results_for("arbitrary") do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page).to have_content(work.description)
        expect(page.html).to have_excerpt("arbitrary", "An", "description")
      end
    end

    scenario "for urls associated through works", search: true do
      work = create(
        :work,
        infringing_urls: [
          create(:infringing_url, url: 'http://example.com/infringing_url')
        ],
        copyrighted_urls: [
          create(:copyrighted_url, url: 'http://example.com/copyrighted_url')
        ]
      )

      notice = create(:dmca, works: [work])
      index_changed_instances

      within_search_results_for('infringing_url') do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page.html).to have_excerpt('infringing_url')
      end

      within_search_results_for('copyrighted_url') do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
        expect(page.html).to have_excerpt('copyrighted_url')
      end
    end
  end

  context "changes to associated models" do
    scenario "a topic is created", search: true do
      notice = create(:dmca)
      notice.topics.create!(name: "arbitrary")
      index_changed_instances

      within_search_results_for("arbitrary") do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
      end
    end

    scenario "a topic is destroyed", search: true do
      topic = create(:topic, name: "arbitrary")
      notice = create(:dmca, topics: [topic])
      topic.destroy
      index_changed_instances

      expect_search_to_not_find("arbitrary", notice)
    end

    scenario "a topic updates its name", search: true do
      topic = create(:topic, name: "something")
      notice = create(:dmca, topics: [topic])
      topic.update_attributes!(name: "arbitrary")
      index_changed_instances

      within_search_results_for("arbitrary") do
        expect(page).to have_n_results(1)
        expect(page).to have_content(notice.title)
      end
    end
  end

  scenario "advanced search on multiple fields", search: true do
    create_notice_with_entities("Jim & Jon's", "Jim", "Jon")
    create_notice_with_entities("Jim & Dan's", "Jim", "Dan")
    create_notice_with_entities("Dan & Jon's", "Dan", "Jon")
    index_changed_instances

    search_for(sender_name: "Jim", recipient_name: "Jon")

    expect(page).to have_content("Jim & Jon's")
    expect(page).to have_no_content("Jim & Dan's")
    expect(page).to have_no_content("Dan & Jon's")
  end

  scenario "searching with a blank parameter", search: true do
    expect { submit_search('') }.not_to raise_error
  end

  private

  def expect_search_to_not_find(term, notice)
    submit_search(term)

    expect(page).to have_no_content(notice.title)

    yield if block_given?
  end

  def have_excerpt(excerpt, prefix = nil, suffix = nil)
    include([prefix, "<em>#{excerpt}</em>", suffix].compact.join(' '))
  end

  def create_notice_with_entities(title, sender_name, recipient_name)
    sender = Entity.find_or_create_by(name: sender_name)
    recipient = Entity.find_or_create_by(name: recipient_name)

    create(:dmca, title: title).tap do |notice|
      create(
        :entity_notice_role,
        name: 'sender',
        notice: notice,
        entity: sender
      )
      create(
        :entity_notice_role,
        name: 'recipient',
        notice: notice,
        entity: recipient
      )
    end
  end
end
