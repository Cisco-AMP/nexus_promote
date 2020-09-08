# frozen_string_literal: true
require 'colorize'
require 'nexus_api'
require 'open3'
require 'pry'

NEXUS_USERNAME=ENV['NEXUS_USERNAME']
NEXUS_PASSWORD=ENV['NEXUS_PASSWORD']
NEXUS_HOSTNAME='nexus.example.com' # Put your Nexus server's hostname here

LATEST_REPO='yum_latest'
QA_REPO='yum_qa'
PROD_REPO='yum_prod'
NEXUS_REPOS=[LATEST_REPO, QA_REPO, PROD_REPO]

LATEST_TAG='latest_external_yum_asset'
QA_TAG='yum_qa_1111111111'
QA_FUTURE_TAG='yum_qa_9999999999'
PROD_TAG='yum_prod_1111111111'
NEXUS_TAGS=[PROD_TAG, QA_TAG, QA_FUTURE_TAG, LATEST_TAG]

LATEST_ASSET='asset_3.rpm'
QA_ASSET='asset_2.rpm'
QA_FUTURE_ASSET='asset_4.rpm'
PROD_ASSET='asset_1.rpm'

$LOAD_PATH.unshift(File.join(__dir__, '../test'))
require 'nexus_promote_helpers'
include NexusPromoteHelpers

def test_setup
  valid_nexus_credentials?
  testing_in_qa?
  @nexus_api =  NexusAPI::API.new(
    username: NEXUS_USERNAME,
    password: NEXUS_PASSWORD,
    hostname: NEXUS_HOSTNAME
  )
  create_tags
  remove_repos
  create_repos
  populate_repos
end

def verify_qa_promote
  # verify old tag has been deleted
  tags = get_tag_names
  fail_test("Failed to delete old QA tag '#{QA_TAG}'") if tags.include?(QA_TAG)

  # verify future package in QA but not promoted package 
  qa_assets = get_assets(QA_REPO)
  error = "'#{QA_FUTURE_ASSET}' is missing from #{QA_REPO}"
  fail_test(error) unless qa_assets.include?(QA_FUTURE_ASSET)
  fail_test("Failed to promote '#{QA_ASSET}' from #{QA_REPO}") if qa_assets.include?(QA_ASSET)

  # verify promoted package in Prod but not future package 
  prod_assets = get_assets(PROD_REPO)
  error = "'#{QA_FUTURE_ASSET}' should not have been promoted to #{PROD_REPO}"
  fail_test(error) if prod_assets.include?(QA_FUTURE_ASSET)
  error = "Failed to promote '#{QA_ASSET}' to #{PROD_REPO}"
  fail_test(error) unless prod_assets.include?(QA_ASSET)

  # verify promoted package had its QA tag replaced with Prod
  prod_components = get_components(PROD_REPO)
  tag_verified = verify_tags(prod_components, QA_ASSET, QA_TAG, PROD_REPO)
  fail_test("Could not find '#{QA_ASSET}' in #{PROD_REPO}") unless tag_verified
end

def verify_latest_promote
  # verify old tag still exists
  tags = get_tag_names
  error = "Latest tag '#{LATEST_TAG}' was NOT supposed to be deleted"
  fail_test(error) unless tags.include?(LATEST_TAG)

  # verify promoted package not in latest
  latest_assets = get_assets(LATEST_REPO)
  error = "Failed to promote '#{LATEST_ASSET}' from #{LATEST_REPO}"
  fail_test(error) if latest_assets.include?(LATEST_ASSET)

  # verify promoted package in QA
  qa_assets = get_assets(QA_REPO)
  error = "Failed to promote '#{LATEST_ASSET}' to #{QA_REPO}"
  fail_test(error) unless qa_assets.include?(LATEST_ASSET)

  # verify promoted package had its latest tag replaced with QA
  qa_components = get_components(QA_REPO)
  tag_verified = verify_tags(qa_components, LATEST_ASSET, LATEST_TAG, QA_REPO)
  fail_test("Could not find '#{LATEST_ASSET}' in #{QA_REPO}") unless tag_verified
end

def test_run
  # We're running bundle within bundle so we need to reset the environment since
  # the default behaviour is to only load one context and ignore subsequent ones
  Bundler.with_clean_env do
    Dir.chdir '..' do
      stdout, stderr, status = Open3.capture3('script/bootstrap')
      error = "Problem setting up nexus_promote:\n#{stderr}"
      fail_test(error) unless status.exitstatus == 0

      run_nexus_promote(QA_REPO, PROD_REPO)
      verify_qa_promote

      run_nexus_promote(LATEST_REPO, QA_REPO, tag=LATEST_TAG)
      verify_latest_promote
    end
  end
end

def test_teardown
  cleanup_tags
  remove_repos
end


# TEST EXECUTION
test_setup
begin
  test_run
  puts "Tests were successful!".green
rescue StandardError => error
  puts error
ensure
  test_teardown
end
