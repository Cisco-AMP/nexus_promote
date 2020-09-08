require 'nexus_promote'

RSpec.describe 'NexusPromote::Manager' do
  let(:api) { double }
  let(:new_tag) { 'new_tag' }
  let(:old_tag) { 'old_tag' }

  before(:each) do
    @manager = NexusPromote::Manager.new(nil)
    @manager.api = api
  end

  describe '#setup_tag' do
    it 'creates a new tag' do
      @manager.all_tags = []
      expect(api).to receive(:create_tag).with({name: new_tag}).and_return(true)
      @manager.setup_tag(new_tag)
    end

    it 'fails if the tag is not unique' do
      @manager.all_tags = [{'name' => new_tag}]
      expect(api).to_not receive(:create_tag)
      expect { @manager.setup_tag(new_tag) }.to raise_error(SystemExit)
    end

    it 'fails if the tag is not created' do
      @manager.all_tags = []
      expect(api).to receive(:create_tag).with({name: new_tag}).and_return(false)
      expect { @manager.setup_tag(new_tag) }.to raise_error(SystemExit)
    end
  end

  describe '#generate_tags' do
    it 'returns tag names that contain the source repo in the name' do
      repo_match = {'name' => 'a_source_repo_1111111111'}
      repo_no_match = {'name' => 'not_a_match_1111111111'}
      @manager.all_tags = [repo_match, repo_no_match]
      expect(@manager.generate_tags(0)).to eq([repo_match['name']])
    end

    it 'returns tag names older than the current time minus the filter' do
      repo_match = {'name' => 'a_source_repo_1111111111'}
      repo_no_match = {'name' => 'a_source_repo_9999999999'}
      @manager.all_tags = [repo_match, repo_no_match]
      expect(@manager.generate_tags(1000)).to eq([repo_match['name']])
    end
  end

  describe '#move' do
    before(:each) do
      allow(api).to receive(:move_components_to)
    end

    it 'promotes assets with the old tag from the source to the destination repo' do
      arguments = {
        tag: old_tag,
        source: ENV['SOURCE_REPO'],
        destination: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([1])
      expect(api).to receive(:move_components_to).with(arguments).and_return(true)
      @manager.move(old_tag)
    end

    it 'does not promote when no matching assets are found' do
      arguments = {
        tag: old_tag,
        source: ENV['SOURCE_REPO'],
        destination: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([])
      expect(api).to_not receive(:move_components_to)
      @manager.move(old_tag)
    end
  end

  describe '#retag' do
    before(:each) do
      allow(api).to receive(:associate_tag)
      allow(api).to receive(:delete_associated_tag)
    end

    it 'associates the new tag to assets in the destination repo with the old tag' do
      arguments = {
        tag: old_tag,
        name: new_tag,
        repository: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([1])
      expect(api).to receive(:associate_tag).with(arguments)
      @manager.retag(new_tag, old_tag)
    end

    it 'does not affect tags when no matches are found' do
      arguments = {
        tag: old_tag,
        name: new_tag,
        repository: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([])
      expect(api).to_not receive(:associate_tag)
      expect(api).to_not receive(:delete_associated_tag)
      @manager.retag(new_tag, old_tag)
    end

    it 'removes the old tag from assets after they have been retagged' do
      arguments = {
        tag: old_tag,
        name: old_tag,
        repository: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([1])
      expect(api).to receive(:associate_tag).and_return(true)
      expect(api).to receive(:delete_associated_tag).with(arguments)
      @manager.retag(new_tag, old_tag)
    end

    it 'does not remove the old tag from assets when they are not retagged' do
      arguments = {
        tag: old_tag,
        name: old_tag,
        repository: ENV['DESTINATION_REPO']
      }
      expect(@manager).to receive(:get_all_tagged_components).and_return([1])
      expect(api).to receive(:associate_tag).and_return(false)
      expect(api).to_not receive(:delete_associated_tag).with(arguments)
      @manager.retag(new_tag, old_tag)
    end
  end
end