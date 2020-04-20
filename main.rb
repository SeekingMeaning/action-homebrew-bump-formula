# frozen_string_literal: true

class Object
  def false?
    nil?
  end
end

class String
  def false?
    empty? || strip == 'false'
  end
end

module Homebrew
  module_function

  def brew(*args)
    puts "[command]brew #{args.join(' ')}"
    return if ENV['DEBUG']

    safe_system('brew', *args)
  end

  def git(*args)
    puts "[command]git #{args.join(' ')}"
    return if ENV['DEBUG']

    safe_system('git', *args)
  end

  # Get inputs
  token = ENV['INPUT_TOKEN']
  tap = ENV['INPUT_TAP']
  formula = ENV['INPUT_FORMULA']
  tag = ENV['INPUT_TAG']
  revision = ENV['INPUT_REVISION']
  force = ENV['INPUT_FORCE']
  livecheck = ENV['INPUT_LIVECHECK']

  # Set needed HOMEBREW environment variables
  ENV['HOMEBREW_GITHUB_API_TOKEN'] = token

  # Get user details
  actor = ENV['GITHUB_ACTOR']
  user = GitHub.open_api "#{GitHub::API_URL}/users/#{actor}"
  user_name = user['name'] || user['login']
  user_email = user['email'] || (
    # https://help.github.com/en/github/setting-up-and-managing-your-github-user-account/setting-your-commit-email-address
    user_created_at = Date.parse user['created_at']
    plus_after_date = Date.parse '2017-07-18'
    need_plus_email = (user_created_at - plus_after_date).positive?
    user_email = "#{actor}@users.noreply.github.com"
    user_email = "#{user['id']}+#{user_email}" if need_plus_email
    user_email
  )

  # Tell git who you are
  git 'config', '--global', 'user.name', user_name
  git 'config', '--global', 'user.email', user_email

  # Update Homebrew
  brew 'update-reset'

  # Tap the tap if desired and change the formula name to full name
  if tap
    brew 'tap', tap
    formula = tap + '/' + formula
  end

  # Do livecheck stuff
  if livecheck
    # Tap livecheck command
    brew 'tap', 'homebrew/livecheck'

    # Get livecheck info
    json = Utils.popen_read 'brew', 'livecheck',
                            '--quiet',
                            '--newer-only',
                            '--full-name',
                            '--json',
                            *("--tap=#{tap}" if !tap.blank? && formula.blank?),
                            *(formula unless formula.blank?)
    json = JSON.parse json

    # Loop over livecheck info
    json.each do |info|
      # Get info about formula
      formula = info['formula']
      stable = Formula[formula].stable
      is_git = stable.downloader.is_a? GitDownloadStrategy

      # Prepare tag and revision or url
      if is_git
        tag = stable.specs[:tag].gsub stable.version, info['version']['latest']
        revision = Utils.popen_read 'git', 'ls-remote', '-t', stable.url, tag
        revision = revision.split("\t").first
      else
        url = stable.url.gsub stable.version, info['version']['latest']
      end

      # Finally bump the formula
      brew 'bump-formula-pr',
           '--no-audit',
           '--no-browse',
           '--message=[`action-homebrew-bump-formula`](https://github.com/dawidd6/action-homebrew-bump-formula)',
           *("--url=#{url}" unless is_git),
           *("--tag=#{tag}" if is_git),
           *("--revision=#{revision}" if is_git),
           *('--force' unless force.false?),
           formula
    end

    exit
  end

  # Get info about formula
  stable = Formula[formula].stable
  is_git = stable.downloader.is_a? GitDownloadStrategy

  # Prepare tag and url
  tag = tag.delete_prefix 'refs/tags/'
  url = stable.url.gsub stable.version, Version.parse(tag)

  # Finally bump the formula
  brew 'bump-formula-pr',
       '--no-audit',
       '--no-browse',
       '--message=[`action-homebrew-bump-formula`](https://github.com/dawidd6/action-homebrew-bump-formula)',
       *("--url=#{url}" unless is_git),
       *("--tag=#{tag}" if is_git),
       *("--revision=#{revision}" if is_git),
       *('--force' unless force.false?),
       formula
end
