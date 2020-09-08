module NexusPromoteHelpers
  def valid_nexus_credentials?
    error = "Nexus credentials have not been set."
    fail_test(error) if NEXUS_USERNAME.nil? || NEXUS_PASSWORD.nil?
  end

  def testing_in_qa?
    error = "It is UNSAFE to run these tests OUTSIDE of a test environment\n"\
      "  Server under test: #{NEXUS_HOSTNAME}\n"
    fail_test(error) unless NEXUS_HOSTNAME.include?('qa') # Modify this to match a unique part of your test server's domain
  end

  def list(method, arguments={})
    arguments.merge!({paginate: true})
    Array.new.tap do |set|
      loop do
        set.concat(@nexus_api.send(method, arguments))
        break unless @nexus_api.paginate?
      end
    end
  end

  def get_tag_names
    list(:list_tags).map{ |tag| tag['name'] }
  end

  def get_assets(repo)
    list(:list_assets, {repository: repo}).map{ |asset| asset['path'].split('/').last }
  end

  def get_components(repo)
    list(:list_components, {repository: repo})
  end

  def create_tags
    tags = get_tag_names
    NEXUS_TAGS.each do |tag|
      unless tags.include?(tag)
        test_info("Creating tag: #{tag}")
        @nexus_api.create_tag(name: tag)
      end
    end
  end

  def remove_repos
    repositories = @nexus_api.list_repositories.map{ |tag| tag['name'] }
    NEXUS_REPOS.each do |repo|
      if repositories.include?(repo)
        test_info("Deleting repository: #{repo}")
        @nexus_api.delete_repository(name: repo)
      end
    end
  end

  def create_repos
    NEXUS_REPOS.each do |repo|
      test_info("Creating repository: #{repo}")
      @nexus_api.create_repository_yum_hosted(name: repo, depth: 0)
    end
  end

  def upload_asset(name, repo, tag)
    test_info("Uploading test asset #{name} to #{repo} with tag #{tag}")
    @nexus_api.upload_yum_component(
      filename: name,
      directory: '',
      repository: repo,
      tag: tag
    )
  end

  def populate_repos
    upload_asset("assets/#{PROD_ASSET}", PROD_REPO, PROD_TAG)
    upload_asset("assets/#{QA_ASSET}", QA_REPO, QA_TAG)
    upload_asset("assets/#{LATEST_ASSET}", LATEST_REPO, LATEST_TAG)
    upload_asset("assets/#{QA_FUTURE_ASSET}", QA_REPO, QA_FUTURE_TAG)
  end

  def sanitize(command)
    entries = command.split(' ')
    entries.map do |entry|
      if entry.include?('NEXUS_USERNAME') || entry.include?('NEXUS_PASSWORD')
        entry.split('=')[0] + '=[REDACTED]'
      else
        entry
      end
    end.join(' ')
  end

  def fail_test(message)
    puts "FAILURE: #{message}".red
    exit 1
  end

  def test_info(message)
    puts "INFO: #{message}".yellow
  end

  def verify_tags(components, promoted_asset, old_tag, new_tag)
    done = false
    components.each do |component|
      component['assets'].each do |asset|
        if promoted_asset == asset['path'].split('/').last
          error = "'#{promoted_asset}' still has the '#{old_tag}' tag"
          fail_test(error) if component['tags'].include?(old_tag)

          if component['tags'].select { |tag| tag.include?(new_tag) }.empty?
            test_info("Tags associated to #{promoted_asset}:\n  #{component['tags']}")
            error = "'#{promoted_asset}' did not get retagged with #{new_tag}"
            fail_test(error)
          end

          done = true
          break
        end
      end
      break if done
    end
    done
  end

  def cleanup_tags
    get_tag_names.each do |tag|
      NEXUS_REPOS.each do |repo|
        if tag.include?(repo) && !NEXUS_TAGS.include?(tag)
          test_info("Deleting tag '#{tag}'")
          @nexus_api.delete_tag(name: tag)
        end
      end
    end
  end

  def run_nexus_promote(source, destination, tag=nil, threshold=nil)
    environment = "NEXUS_USERNAME=#{NEXUS_USERNAME} "\
      "NEXUS_PASSWORD=#{NEXUS_PASSWORD} "\
      "NEXUS_HOSTNAME=#{NEXUS_HOSTNAME} "\
      "SOURCE_REPO=#{source} "\
      "DESTINATION_REPO=#{destination} "\
      "VERBOSE=true "\
      "TIMEOUT=0"

    command = "#{environment} bundle exec bin/nexus_promote"
    command += " --tag_to_promote #{tag}" unless tag.nil?
    command += " --threshold #{threshold}" unless threshold.nil?
    test_info("Running command:\n  #{sanitize(command)}")

    stdout, stderr, status = Open3.capture3(command)
    error = "Problem running nexus_promote:\n#{stderr}"
    fail_test(error) unless status.exitstatus == 0
    puts stdout
  end
end