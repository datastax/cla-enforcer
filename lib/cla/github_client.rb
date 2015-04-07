module CLA
  class GithubClient
    def initialize(octokit, tagged_pulls, contributors, hostname, github_hostname, github_verifier, label_name, label_color)
      @octokit         = octokit
      @tagged_pulls    = tagged_pulls
      @contributors    = contributors
      @hostname        = hostname
      @github_hostname = github_hostname
      @github_verifier = github_verifier
      @label_name      = label_name
      @label_color     = label_color

      @request_signature_template = ERB.new(
        File.read(
          File.expand_path('../../templates/request_signature.md.erb', __FILE__)
        )
      )
      @cla_signed_template = ERB.new(
        File.read(
          File.expand_path('../../templates/cla_signed.md.erb', __FILE__)
        )
      )
      @cla_enabled_template = ERB.new(
        File.read(
          File.expand_path('../../templates/cla_enabled.md.erb', __FILE__)
        )
      )
    end

    def request_signature(user, repo, number, login)
      @octokit.add_comment("#{user}/#{repo}", number,
        @request_signature_template.result(binding)
      )
      @octokit.update_issue("#{user}/#{repo}", number, labels: [@label_name])
      @tagged_pulls.insert({
        login:  login,
        user:   user,
        repo:   repo,
        number: number
      })
      nil
    end

    def confirm_signature(user, repo, number, login)
      @octokit.add_comment("#{user}/#{repo}", number,
        @cla_signed_template.result(binding)
      )
      labels = get_labels("#{user}/#{repo}", number)

      if labels.any? {|l| l[:name] == @label_name}
        labels = labels.each_with_object([]) do |label, list|
          list << label[:name] unless label[:name] == @label_name
        end
        @octokit.update_issue("#{user}/#{repo}", number, labels: labels)
      end
      nil
    end

    def signature_complete(login)
      @tagged_pulls.where(login: login).each do |row|
        user   = row[:user]
        repo   = row[:repo]
        number = row[:number]

        @octokit.add_comment("#{user}/#{repo}", number,
          @cla_signed_template.result(binding)
        )
        labels = get_labels("#{user}/#{repo}", number)

        if labels.any? {|l| l[:name] == @label_name}
          labels = labels.each_with_object([]) do |label, list|
            list << label[:name] unless label[:name] == @label_name
          end
          @octokit.update_issue("#{user}/#{repo}", number, labels: labels)
        end
        @tagged_pulls.where(id: row[:id]).delete
      end
    end

    def collaborator?(user, repo, login)
      @octokit.collaborator?("#{user}/#{repo}", login)
    end

    def subscribe(repo, uri)
      res =  []
      res << @octokit.subscribe(File.join(@github_hostname, repo, 'events/pull_request'), File.join(@hostname, uri), @github_verifier)
      res << @octokit.subscribe(File.join(@github_hostname, repo, 'events/issue_comment'), File.join(@hostname, uri), @github_verifier)
      res << @octokit.add_label(repo, @label_name, @label_color) rescue 'label exists'
      res
    end

    def missing(repo)
      contributors  = @octokit.contributors(repo).map(&:login)
      collaborators = @octokit.collaborators(repo).map(&:login)

      collaborators.each do |login|
        contributors.delete(login)
      end
      @contributors.where(login: contributors, status: 'Completed').select(:login).each do |row|
        contributors.delete(row[:login])
      end

      contributors.map {|login| "@#{login}"}
    end

    def announce(repo, agreement_name)
      contributors  = @octokit.contributors(repo).map(&:login)
      collaborators = @octokit.collaborators(repo).map(&:login)

      collaborators.each do |login|
        contributors.delete(login)
      end
      @contributors.where(login: contributors, status: 'Completed').select(:login).each do |row|
        contributors.delete(row[:login])
      end
      @tagged_pulls.where(login: contributors).select(:login).each do |row|
        contributors.delete(row[:login])
      end

      unless contributors.empty?
        issue = @octokit.create_issue(repo, agreement_name,
          @cla_enabled_template.result(binding)
        )
        user, repo = repo.split('/', 2)

        contributors.each do |login|
          @tagged_pulls.insert({
            login:  login,
            user:   user,
            repo:   repo,
            number: issue.number
          })
        end
      end
    end

    private

    def get_labels(repo, number)
      @octokit.paginate "#{Octokit::Repository.path repo}/issues/#{number}/labels", {}
    end
  end
end
