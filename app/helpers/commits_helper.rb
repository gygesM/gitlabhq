module CommitsHelper
  # Returns a link to the commit author. If the author has a matching user and
  # is a member of the current @project it will link to the team member page.
  # Otherwise it will link to the author email as specified in the commit.
  #
  # options:
  #  avatar: true will prepend the avatar image
  #  size:   size of the avatar image in px
  def commit_author_link(commit, options = {})
    commit_person_link(commit, options.merge(source: :author))
  end

  # Just like #author_link but for the committer.
  def commit_committer_link(commit, options = {})
    commit_person_link(commit, options.merge(source: :committer))
  end

  def image_diff_class(diff)
    if diff.deleted_file
      "deleted"
    elsif diff.new_file
      "added"
    else
      nil
    end
  end

  def commit_to_html(commit, ref, project)
    render 'projects/commits/commit',
      commit: commit,
      ref: ref,
      project: project
  end

  # Breadcrumb links for a Project and, if applicable, a tree path
  def commits_breadcrumbs
    return unless @project && @ref

    # Add the root project link and the arrow icon
    crumbs = content_tag(:li) do
      link_to(
        @project.path,
        namespace_project_commits_path(@project.namespace, @project, @ref)
      )
    end

    if @path
      parts = @path.split('/')

      parts.each_with_index do |part, i|
        crumbs << content_tag(:li) do
          # The text is just the individual part, but the link needs all the parts before it
          link_to(
            part,
            namespace_project_commits_path(
              @project.namespace,
              @project,
              tree_join(@ref, parts[0..i].join('/'))
            )
          )
        end
      end
    end

    crumbs.html_safe
  end

  # Return Project default branch, if it present in array
  # Else - first branch in array (mb last actual branch)
  def commit_default_branch(project, branches)
    branches.include?(project.default_branch) ? branches.delete(project.default_branch) : branches.pop
  end

  # Returns the sorted alphabetically links to branches, separated by a comma
  def commit_branches_links(project, branches)
    branches.sort.map do |branch|
      link_to(project_ref_path(project, branch), class: "label label-gray ref-name") do
        icon('code-fork') + " #{branch}"
      end
    end.join(" ").html_safe
  end

  # Returns the sorted links to tags, separated by a comma
  def commit_tags_links(project, tags)
    sorted = VersionSorter.rsort(tags)
    sorted.map do |tag|
      link_to(project_ref_path(project, tag), class: "label label-gray ref-name") do
        icon('tag') + " #{tag}"
      end
    end.join(" ").html_safe
  end

  def link_to_browse_code(project, commit)
    return unless current_controller?(:commits)

    if @path.blank?
      return link_to(
        "Browse Files",
        namespace_project_tree_path(project.namespace, project, commit),
        class: "btn btn-default"
      )
    elsif @repo.blob_at(commit.id, @path)
      return link_to(
        "Browse File",
        namespace_project_blob_path(project.namespace, project,
                                    tree_join(commit.id, @path)),
        class: "btn btn-default"
      )
    elsif @path.present?
      return link_to(
        "Browse Directory",
        namespace_project_tree_path(project.namespace, project,
                                    tree_join(commit.id, @path)),
        class: "btn btn-default"
      )
    end
  end

  def revert_commit_link(commit, continue_to_path, btn_class: nil, has_tooltip: true)
    commit_action_link('revert', commit, continue_to_path, btn_class: btn_class, has_tooltip: has_tooltip)
  end

  def cherry_pick_commit_link(commit, continue_to_path, btn_class: nil, has_tooltip: true)
    commit_action_link('cherry-pick', commit, continue_to_path, btn_class: btn_class, has_tooltip: has_tooltip)
  end

  protected

  # Private: Returns a link to a person. If the person has a matching user and
  # is a member of the current @project it will link to the team member page.
  # Otherwise it will link to the person email as specified in the commit.
  #
  # options:
  #  source: one of :author or :committer
  #  avatar: true will prepend the avatar image
  #  size:   size of the avatar image in px
  def commit_person_link(commit, options = {})
    user = commit.send(options[:source])

    source_name = clean(commit.send "#{options[:source]}_name".to_sym)
    source_email = clean(commit.send "#{options[:source]}_email".to_sym)

    person_name = user.try(:name) || source_name

    text =
      if options[:avatar]
        %Q{<span class="commit-#{options[:source]}-name">#{person_name}</span>}
      else
        person_name
      end

    options = {
      class: "commit-#{options[:source]}-link has-tooltip",
      title: source_email
    }

    if user.nil?
      mail_to(source_email, text.html_safe, options)
    else
      link_to(text.html_safe, user_path(user), options)
    end
  end

  def commit_action_link(action, commit, continue_to_path, btn_class: nil, has_tooltip: true)
    return unless current_user

    tooltip = "#{action.capitalize} this #{commit.change_type_title(current_user)} in a new merge request" if has_tooltip
    btn_class = "btn btn-#{btn_class}" unless btn_class.nil?

    if can_collaborate_with_project?
      link_to action.capitalize, "#modal-#{action}-commit", 'data-toggle' => 'modal', 'data-container' => 'body', title: (tooltip if has_tooltip), class: "#{btn_class} #{'has-tooltip' if has_tooltip}"
    elsif can?(current_user, :fork_project, @project)
      continue_params = {
        to: continue_to_path,
        notice: "#{edit_in_new_fork_notice} Try to #{action} this commit again.",
        notice_now: edit_in_new_fork_notice_now
      }
      fork_path = namespace_project_forks_path(@project.namespace, @project,
        namespace_key: current_user.namespace.id,
        continue: continue_params)

      link_to action.capitalize, fork_path, class: btn_class, method: :post, 'data-toggle' => 'tooltip', 'data-container' => 'body', title: (tooltip if has_tooltip)
    end
  end

  def view_file_button(commit_sha, diff_new_path, project)
    link_to(
      namespace_project_blob_path(project.namespace, project,
                                  tree_join(commit_sha, diff_new_path)),
      class: 'btn view-file js-view-file'
    ) do
      raw('View file @ ') + content_tag(:span, Commit.truncate_sha(commit_sha),
                                       class: 'commit-sha')
    end
  end

  def view_on_environment_button(commit_sha, diff_new_path, environment)
    return unless environment && commit_sha

    external_url = environment.external_url_for(diff_new_path, commit_sha)
    return unless external_url

    link_to(external_url, class: 'btn btn-file-option has-tooltip', target: '_blank', rel: 'noopener noreferrer', title: "View on #{environment.formatted_external_url}", data: { container: 'body' }) do
      icon('external-link')
    end
  end

  def truncate_sha(sha)
    Commit.truncate_sha(sha)
  end

  def clean(string)
    Sanitize.clean(string, remove_contents: true)
  end

  def limited_commits(commits)
    if commits.size > MergeRequestDiff::COMMITS_SAFE_SIZE
      [
        commits.first(MergeRequestDiff::COMMITS_SAFE_SIZE),
        commits.size - MergeRequestDiff::COMMITS_SAFE_SIZE
      ]
    else
      [commits, 0]
    end
  end
end
