require 'rails_helper'

RSpec.describe Work, type: :model do
  it { is_expected.to have_and_belong_to_many :notices }
  it { is_expected.to have_and_belong_to_many :infringing_urls }
  it { is_expected.to have_and_belong_to_many :copyrighted_urls }

  context 'automatic validations' do
    it { is_expected.to validate_length_of(:kind).is_at_most(255) }
  end

  context '.unknown' do
    it 'provides an unknown work' do
      work = Work.unknown

      expect(work.kind).to eq 'unknown'
      expect(work.description).to eq Work::UNKNOWN_WORK_DESCRIPTION
    end

    it 'returns a consistent result' do
      work1 = Work.unknown
      work2 = Work.unknown

      expect(work1).to eq work2
    end

    it 'can be referenced via config' do
      expect(Work.unknown).to eq Lumen::UNKNOWN_WORK
    end
  end

  context '#infringing_urls' do
    it 'does not create duplicate infringing_urls' do
      existing_infringing_url = create(
        :infringing_url, url: 'http://www.example.com/infringe'
      )
      params = { work: { description: 'Test', infringing_urls_attributes:
        [{ url: 'http://www.example.com/infringe' },
         { url: 'http://example.com/new' }] } }
      work = Work.new(params[:work])
      work.save

      work.reload

      expect(work.infringing_urls).to include existing_infringing_url
      expect(InfringingUrl.count).to eq 2
    end
  end

  context '#copyrighted_urls' do
    it 'does not create duplicate copyrighted_urls' do
      existing_copyrighted_url = create(
        :copyrighted_url, url: 'http://www.example.com/copyrighted'
      )

      params = { work: { description: 'Test', copyrighted_urls_attributes:
        [{ url: 'http://www.example.com/copyrighted' },
         { url: 'http://example.com/new' }] } }
      work = Work.new(params[:work])
      work.save

      work.reload

      expect(work.copyrighted_urls).to include existing_copyrighted_url
      expect(CopyrightedUrl.count).to eq 2
    end
  end

  context '#kind' do
    it 'auto classifies before saving if kind is not set' do
      work = build(:work)

      work.save
      expect(work.kind).to eq 'Unspecified'
    end

    it 'does not auto classify if kind is set' do
      expect_any_instance_of(DeterminesWorkKind).not_to receive(:kind)
      work = build(:work, kind: 'foo')

      work.save
    end
  end

  it 'validates infringing urls correctly when multiple are used at once' do
    notice = notice_with_works_attributes(
      [
        { infringing_urls_attributes: [{ url: 'this is not a url' }] },
        { infringing_urls_attributes: [{ url: 'this is also not a url' }] }
      ]
    )

    expect(notice).not_to be_valid
    expect(notice.errors.messages).to eq(
      'works.infringing_urls': ['is invalid']
    )
  end

  it 'validates copyrighted urls correctly when multiple are used at once' do
    notice = notice_with_works_attributes(
      [
        { copyrighted_urls_attributes: [{ url: 'this is not a url' }] },
        { copyrighted_urls_attributes: [{ url: 'this is also not a url' }] }
      ]
    )

    expect(notice).not_to be_valid
    expect(notice.errors.messages).to eq(
      'works.copyrighted_urls': ['is invalid']
    )
  end

  context 'redaction' do
    it 'redacts phone numbers with auto_redact' do
      content = '(617) 867-5309'
      test_redaction(content)
    end

    it 'redacts emails with auto_redact' do
      content = 'me@example.com'
      test_redaction(content)
    end

    it 'redacts SSNs with auto_redact' do
      content = '123-45-6789'
      test_redaction(content)
    end

    it 'redacts automatically on save' do
      params = { description: 'Test' }
      work = Work.new(params)
      expect(work).to receive(:auto_redact)
      work.save
    end
  end

  private

  def notice_with_works_attributes(attributes)
    DMCA.new(
      works_attributes: attributes,
      entity_notice_roles_attributes: [{
        name: 'recipient',
        entity_attributes: { name: 'Recipient' }
      }]
    )
  end

  def work_for_redaction_testing(redact_me)
    params = { description: "Test if we redact #{redact_me}" }
    work = Work.new(params)
    work.auto_redact
    work.save
    work.reload
    work
  end

  def test_redaction(content)
    work = work_for_redaction_testing(content)

    expect(work.description).not_to include content
    expect(work.description_original).to include content
  end
end
