# frozen_string_literal: true

require 'formula'

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

  def print_command(*cmd)
    puts "[command]#{cmd.join(' ').gsub("\n", ' ')}"
  end

  def brew(*args)
    print_command 'brew', *args
    return if ENV['DEBUG']

    safe_system 'brew', *args
  end

  def git(*args)
    print_command 'git', *args
    return if ENV['DEBUG']

    safe_system 'git', *args
  end

  def read_brew(*args)
    print_command 'brew', *args
    return if ENV['DEBUG']

    Utils.safe_popen_read('brew', *args).chomp
  end

  def read_git(*args)
    print_command 'git', *args
    return if ENV['DEBUG']

    Utils.safe_popen_read('git', *args).chomp
  end

  # Get inputs
  token = ENV['TOKEN']
  message = ENV['MESSAGE']
  tap = ENV['TAP']
  formula = ENV['FORMULA']
  version = ENV['VERSION']
  url = ENV['URL']
  tag = ENV['TAG']
  revision = ENV['REVISION']
  force = ENV['FORCE']
  livecheck = ENV['LIVECHECK']

  # Set needed HOMEBREW environment variables
  ENV['HOMEBREW_GITHUB_API_TOKEN'] = token

  # Check inputs
  if livecheck.false?
    odie "Need 'formula' input specified" if formula.blank?
    odie "Need 'version', 'url', or 'tag' input specified" if [version, url, tag].all?(&:blank?)
    odie "Need 'revision' input specified" if tag.present? && revision.blank?
  end

  # Get user details
  user = GitHub.open_api "#{GitHub::API_URL}/user"
  user_id = user['id']
  user_login = user['login']
  user_name = user['name'] || user['login']
  user_email = user['email'] || (
    # https://help.github.com/en/github/setting-up-and-managing-your-github-user-account/setting-your-commit-email-address
    user_created_at = Date.parse user['created_at']
    plus_after_date = Date.parse '2017-07-18'
    need_plus_email = (user_created_at - plus_after_date).positive?
    user_email = "#{user_login}@users.noreply.github.com"
    user_email = "#{user_id}+#{user_email}" if need_plus_email
    user_email
  )

  # Tell git who you are
  git 'config', '--global', 'user.name', user_name
  git 'config', '--global', 'user.email', user_email

  # Tap the tap if desired
  brew 'tap', tap unless tap.blank?

  # Append additional PR message
  message = if message.blank?
              ''
            else
              message + "\n\n"
            end
  message += '[`action-homebrew-bump-formula`](https://github.com/dawidd6/action-homebrew-bump-formula)'

  # Do the livecheck stuff or not
  if livecheck.false?
    # Change formula name to full name
    formula = tap + '/' + formula if !tap.blank? && !formula.blank?

    # Prepare tag
    tag = tag.delete_prefix('refs/tags/') if tag.present?

    # Finally bump the formula
    brew 'bump-formula-pr',
         '--no-audit',
         '--no-browse',
         "--message=#{message}",
         *("--version=#{version}" if version.present?),
         *("--url=#{url}" if url.present?),
         *("--tag=#{tag}" if tag.present?),
         *("--revision=#{revision}" if revision.present?),
         *('--force' unless force.false?),
         formula
  else
    # Support multiple formulae in input and change to full names if tap
    unless formula.blank?
      formula = formula.split(/[ ,\n]/).reject(&:blank?)
      formula = formula.map { |f| tap + '/' + f } unless tap.blank?
    end

    # Get livecheck info
    json = read_brew 'livecheck',
                     '--quiet',
                     '--newer-only',
                     '--full-name',
                     '--json',
                     *("--tap=#{tap}" if !tap.blank? && formula.blank?),
                     *(formula unless formula.blank?)
    json = JSON.parse json

    # Define error
    err = nil

    # Loop over livecheck info
    json.each do |info|
      # Skip if there is no version field
      next unless info['version']

      # Get info about formula
      formula = info['formula']
      version = info['version']['latest']

      begin
        # Finally bump the formula
        brew 'bump-formula-pr',
             '--no-audit',
             '--no-browse',
             "--message=#{message}",
             "--version=#{version}",
             *('--force' unless force.false?),
             formula
      rescue ErrorDuringExecution => e
        # Continue execution on error, but save the exeception
        err = e
      end
    end

    # Die if error occured
    odie err if err
  end
end
