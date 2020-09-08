require 'nexus_promote/version'
require 'nexus_api'
require 'dotenv'
require 'pry'

Dotenv.load(
  '.env.test.local',
  '.env.production.local',
  '.env'
)

module NexusPromote
  class Manager
    SOURCE_REPO = ENV['SOURCE_REPO']
    DESTINATION_REPO = ENV['DESTINATION_REPO']
    TAG_WHITELIST = ['latest_external_yum_asset']

    attr_accessor :api, :all_tags

    def initialize(tag_to_promote)
      @tag_to_promote = tag_to_promote

      log "Using Nexus server '#{ENV['NEXUS_HOSTNAME']}'"
      @api = NexusAPI::API.new(
        username: ENV['NEXUS_USERNAME'],
        password: ENV['NEXUS_PASSWORD'],
        hostname: ENV['NEXUS_HOSTNAME']
      )
    end

    def setup_tag(new_tag)
      log "Ensuring new tag '#{new_tag}' is unique..."

      if @all_tags.map{ |tag| tag['name'] }.include?(new_tag)
        error_out(additional_info:
          "ERROR: Tag '#{new_tag}' already exists in Nexus.\n"\
          "       Re-using this tag could cause issues.\n"\
          "       Try re-running the script to generate a new tag."
        )
      end

      log 'Creating new tag...'
      result = @api.create_tag(name: new_tag)
      unless result
        error_out(additional_info: "Tag creation failed. Does the name contain invalid characters?")
      end
    end

    def generate_tags(threshold)
      log "Finding tags older than #{threshold} seconds with '#{SOURCE_REPO}' in the name..."
      source_tags = @all_tags.select do |tag|
        tag['name'].include?(SOURCE_REPO)
      end
      source_tags.select do |tag|
        time = tag['name'].split('_').last
        tag_timestamp = DateTime.strptime(time, '%s')
        relative_threshold = (Time.now - threshold).to_datetime
        tag_timestamp < relative_threshold
      end.map { |tag| tag['name'] }
    end

    def move(old_tag)
      log "Finding assets with the tag #{old_tag} in #{SOURCE_REPO}..."
      promotable = get_all_tagged_components(SOURCE_REPO, old_tag)

      unless promotable.empty?
        log "Found the following components to move:\n  #{promotable}"
        log "Promoting assets with tag '#{old_tag}' in '#{SOURCE_REPO}' to '#{DESTINATION_REPO}'"
        result = @api.move_components_to(
          destination: DESTINATION_REPO,
          source: SOURCE_REPO,
          tag: old_tag
        )
        if result == true
          timeout = ENV['TIMEOUT'].nil? ? 40 : ENV['TIMEOUT'].to_i
          log "Sleeping #{timeout} seconds so Nexus has time to regerate yum repodata..."
          sleep timeout
        else
          log 'ERROR: nexus_api reported a failure during the promotion. Check the logs.'
        end
      end
    end

    def retag(new_tag, old_tag)
      log "Finding assets with the tag #{old_tag} in #{DESTINATION_REPO}..."
      promotable = get_all_tagged_components(DESTINATION_REPO, old_tag)

      unless promotable.empty?
        log "Found the following components to retag:\n  #{promotable}"
        log "Re-tagging all assets with tag '#{old_tag}' in '#{DESTINATION_REPO}' with new tag '#{new_tag}'..."
        result = @api.associate_tag(name: new_tag, repository: DESTINATION_REPO, tag: old_tag)
        if result == false
          log 'ERROR: nexus_api reported a failure during the retagging. Check the logs.'
        else
          result = @api.delete_associated_tag(name: old_tag, repository: DESTINATION_REPO, tag: old_tag)
          if result == true
            unless TAG_WHITELIST.include?(old_tag)
              log "Removing old tag '#{old_tag}'"
              @api.delete_tag(name: old_tag)
            end
          end
        end
      end
    end

    def promote(new_tag, old_tag)
      move(old_tag)
      retag(new_tag, old_tag)
    end

    def punch_in(threshold)
      @all_tags = get_all_tags

      tags_to_promote = @tag_to_promote.nil? ? generate_tags(threshold) : [@tag_to_promote]
      if tags_to_promote.empty?
        log 'Did not find any valid tags to promote.'
      else
        log "Promoting assets with the following tags:\n  #{tags_to_promote}"
        new_tag = "#{DESTINATION_REPO}_#{Time.now.to_i}"
        setup_tag(new_tag)
        log "Promoting assets from '#{SOURCE_REPO}' to '#{DESTINATION_REPO}'..."
        tags_to_promote.each { |old_tag| promote(new_tag, old_tag) }
        log 'Promotion complete!'
      end
    end

    
    private

    def log(message)
      puts message if ENV['VERBOSE']
    end

    def error_out(additional_info: nil)
      log 'Script failed.'
      log additional_info unless additional_info.nil?
      exit 1
    end

    def get_all_tags
      Array.new.tap do |set|
        loop do
          set.concat(@api.list_tags(paginate: true))
          break unless @api.paginate?
        end
      end
    end

    def get_all_tagged_components(repository, old_tag)
      components = Array.new.tap do |set|
        loop do
          set.concat(@api.list_components(repository: repository, paginate: true))
          break unless @api.paginate?
        end
      end
      promotable = components.select do |component|
        component['tags'].include?(old_tag)
      end.map {|match| match['assets'].first['downloadUrl']}
    end
  end
end
