require 'rails_helper'

feature 'Topics' do
  include SearchHelpers

  before :each do
    @topic = create(:topic, name: 'An awesome name')
  end

  scenario 'user views a topic', search: true do
    make_notices(1)
    visit "/topics/#{@topic.id}"

    within('section.topic-notices') do
      expect(page).to have_words Notice.first.title
    end
  end

  context 'notices' do
    it 'shows a list of notices', search: true do
      make_notices(2)
      visit "/topics/#{@topic.id}"

      expect(page).to have_css('.topic-notices li.notice', count: 2)
    end

    it "does not show notices when they aren't there" do
      visit "/topics/#{@topic.id}"

      expect(page).to_not have_css('.topic-notices')
    end
  end

  def make_notices(count)
    count.times do
      create(:dmca, topics: [@topic])
    end
    index_changed_instances
  end
end
