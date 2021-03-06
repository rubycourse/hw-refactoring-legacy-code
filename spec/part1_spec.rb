# This is the autograder for CS169 HW5: Refactoring & Legacy.
# Author: James Eady <jeady@berkeley.edu>

require 'rspec'
require 'nokogiri'
require 'rubygems'
require 'mechanize'
require 'ruby-debug'

uri = ENV['HEROKU_URI']
uri = 'http://' + uri if uri and uri !~ /^http:\/\//
uri = URI.parse(uri) if uri
$host = URI::HTTP.build(:host => uri.host, :port => uri.port).to_s if uri
$admin_user = ENV['ADMIN_USER']
$admin_pass = ENV['ADMIN_PASS']

# Helper functions. Each of these methods also has a test case dedicated to
# performing a sanity check that ensures that each of these methods should
# succeed every time it is called, thus there is no need to do any extra rspec
# expectations to these functions.

# Log in using $user:$pass.
def login(agent, user, pass)
  page = agent.get URI.join($host, 'accounts/login')
  page.form_with(:action => '/accounts/login') do |f|
    f['user[login]'] = user
    f['user[password]'] = pass
    agent.submit f
  end
end

# Post a new article and return its id.
def create_article(agent, title, body)
  title = '[CS169 Autograder] ' + title
  page = agent.get URI.join($host, 'admin/content/new')
  page.form_with(:action => '/admin/content/new') do |f|
    f['article[title]'] = title
    f['article[body_and_extended]'] = body
    article_list = agent.submit f
    new_article_link = article_list.link_with(:text => title)
    new_article_link.href =~ /\/([0-9]+)$/
    return $1
  end
end

# Destroy an article given an id.
def destroy_article(agent, id)
  destroy_page = agent.get URI.join($host, 'admin/content/destroy/' + id)
  destroy_page.form_with(:action => '/admin/content/destroy/' + id) do |f|
    page = agent.submit f
  end
end

# Merge two articles and return the id of the merged article.
def merge_articles(agent, id_1, id_2)
  page = @agent.get URI.join($host, 'admin/content/edit/' + id_1)
  page.forms.each do |f|
    next if f.fields_with(:name => 'merge_with').size != 1
    f['merge_with'] = id_2
    @agent.submit f
    break
  end

  # Locate the merged article
  page = @agent.get URI.join($host, 'admin/content')
  link = page.link_with(:text => /\[CS169 Autograder\]/)
  link.href =~ /\/([0-9]+)$/
  return $1
end

# Destroy all articles whose title contains the string '[CS169 Autograder]'.
def clean_autograder_articles(agent)
  page = agent.get URI.join($host, 'admin/content')
  page.links_with(:text => /\[CS169 Autograder\]/).each do |link|
    link.href =~ /\/([0-9]+)$/
    destroy_article(agent, $1)
  end
end

# Post a comment on the given article with the name 'Joe Snow' and email
# 'joe@snow.com'.
def post_comment(agent, article_id, body)
  page = agent.get URI.join($host, 'comments?article_id=' + article_id)
  page.form_with(:action => /\/comments\?article_id=#{article_id}$/) do |f|
    f['comment[author]'] = 'Joe Snow'
    f['comment[email]'] = 'joe@snow.com'
    f['comment[body]'] = body
    agent.submit f
  end
end

# Destroys a single user given an id. Used in conjunction with
# clean_autograder_publisher.
def destroy_user(agent, id)
  destroy_page = agent.get URI.join($host, '/admin/users/destroy/' + id)
  destroy_page.form_with(:action => '/admin/users/destroy/' + id) do |f|
    page = agent.submit f
  end
end

# Locates and deletes the user with the name cs169_ag_publisher.
def clean_autograder_publisher(agent)
  page = agent.get URI.join($host, 'admin/users')
  page.links_with(:text => /cs169_ag_publisher/).each do |link|
    link.href =~ /\/([0-9]+)$/
    destroy_user(agent, $1)
  end
end

# Creates a user with the blog publisher permissions.
def create_publisher(agent, login, password)
  page = agent.get URI.join($host, 'admin/users/new')
  page.form_with(:action => /\/admin\/users\/new$/) do |f|
    f['user[login]'] = login
    f['user[password]'] = password
    f['user[password_confirmation]'] = password
    f['user[email]'] = 'joe2@snow2.com'
    f['user[profile_id]'] = 2
    page = agent.submit f
  end
end

# These are essentially sanity tests. They ensure that the target is running,
# the supplied admin username and password are correct, and that the target
# is running as expected.
describe 'Typo' do
  it 'should respond to a simple request [0 points]' do
    agent = Mechanize.new
    page = agent.get($host)
  end

  it 'should authenticate the supplied user as an administrator [0 points]' do
    agent = Mechanize.new
    page = agent.get URI.join($host, 'accounts/login')

    page.search('form[action="/accounts/login"]').size.should == 1
    page.form_with(:action => '/accounts/login') do |f|
      f['user[login]'] = $admin_user
      f['user[password]'] = $admin_pass
      page = agent.submit f
      page.body.should include 'Login successful'
      page.body.should_not include 'Login unsuccessful'
    end
  end

  it 'should post new articles [0 points]' do
    agent = Mechanize.new
    login(agent, $admin_user, $admin_pass)
    clean_autograder_articles(agent)

    page = agent.get URI.join($host, 'admin/content/new')
    page.search('form[action="/admin/content/new"]').size.should == 1
    page.form_with(:action => '/admin/content/new') do |f|
      article_title = '[CS169 Autograder] Blag Post 1234'
      f['article[title]'] = article_title
      f['article[body_and_extended]'] = 'Lorem ipsum dolor sit amet 4444'
      article_list = agent.submit f

      article_list.links_with(:text => article_title).size.should == 1
      article_list.link_with(:text => article_title).href =~ /\/([0-9]+)$/
      id = $1

      destroy_path = 'admin/content/destroy/' + id
      destroy_page = agent.get URI.join($host, destroy_path)
      destroy_page.search("form[action='/#{destroy_path}']").size.should == 1
      destroy_page.form_with(:action => "/#{destroy_path}") do |f|
        page = agent.submit f
        page.body.should include 'was deleted successfully'
      end
    end
  end

  it 'should post comments on articles [0 points]' do
    agent = Mechanize.new
    login(agent, $admin_user, $admin_pass)
    clean_autograder_articles(agent)
    id = create_article(agent, 'Blag Post 1234', 'Rawr')

    page = agent.get URI.join($host, 'comments?article_id=' + id)
    page.body.should include 'Rawr'
    page.search("//form[contains(@action, '/comments?article_id=#{id}')]")
    .size.should == 1
    page.form_with(:action => /\/comments\?article_id=#{id}$/) do |f|
      f['comment[author]'] = 'Joe Snow'
      f['comment[email]'] = 'joe@snow.com'
      f['comment[body]'] = 'Lorem ipsum dolor sit amet'
      agent.submit f
      page = agent.get URI.join($host, 'comments?article_id=' + id)
      page.body.should include 'Lorem ipsum dolor sit amet'
    end
  end

  it 'create blog publisher users [0 points]' do
    agent = Mechanize.new
    login(agent, $admin_user, $admin_pass)
    clean_autograder_publisher(agent)

    page = agent.get URI.join($host, 'admin/users/new')
    page.search('//form[contains(@action, "/admin/users/new")]').
        size.should == 1
    page.form_with(:action => /\/admin\/users\/new$/) do |f|
      f['user[login]'] = 'cs169_ag_publisher'
      f['user[password]'] = 'aaaaaaaa'
      f['user[password_confirmation]'] = 'aaaaaaaa'
      f['user[email]'] = 'joe2@snow2.com'
      f['user[profile_id]'] = 2
      page = agent.submit f
      page.body.should include 'was successfully created'
      page.body.should include 'cs169_ag_publisher'
      clean_autograder_publisher(agent)
    end
  end
end

# This is the meat of the grader, testing the article merging functionality.
describe 'The article merge feature' do
  before :all do
    agent = Mechanize.new
    login(agent, $admin_user, $admin_pass)
    clean_autograder_articles(agent)
  end

  before :each do
    @agent = Mechanize.new
    login(@agent, $admin_user, $admin_pass)
  end

  # Clean out any lingering autograder-created articles.
  after :each do
    clean_autograder_articles(@agent)
  end

  it 'should be shown on the article edit page [15 points]' do
    article_id = create_article(@agent,
                                'Blag Post 1234',
                                'Lorem ipsum')

    page = @agent.get URI.join($host, 'admin/content/edit/' + article_id)
    page.body.should include 'Merge Articles'
    page.search('input[name="merge_with"]').size.should == 1
  end

  it 'should create a single merged article [15 points]' do
    ids = [create_article(@agent,
                          'Blag Post A',
                          'Derp derp derp derp 12344321'),
           create_article(@agent,
                          'Blag Post B',
                          'Lorem ipsum dolor sit amet')]
    page = @agent.get URI.join($host, 'admin/content/edit/' + ids[0])
    page.forms.each do |f|
      next if f.fields_with(:name => 'merge_with').size != 1
      f['merge_with'] = ids[1]
      @agent.submit f
      break
    end

    # Locate the merged article
    page = @agent.get URI.join($host, 'admin/content')
    page.links_with(:text => /\[CS169 Autograder\]/).size.should == 1
  end

  it 'should create an article with the text of both original articles ' +
         '[20 points]' do
    ids = [create_article(@agent,
                          'Blag Post A',
                          'Derp derp derp derp 12344321'),
           create_article(@agent,
                          'Blag Post B',
                          'Lorem ipsum dolor sit amet')]
    merged_id = merge_articles(@agent, ids[0], ids[1])

    page = @agent.get URI.join($host, 'admin/content/edit/' + merged_id)
    page.body.should include 'Derp derp derp derp 12344321'
    page.body.should include 'Lorem ipsum dolor sit amet'
  end

  it 'should carry over the comments from both merged articles [20 points]' do
    ids = [create_article(@agent,
                          'Blag Post A',
                          'Derp derp derp derp 12344321'),
           create_article(@agent,
                          'Blag Post B',
                          'Lorem ipsum dolor sit amet')]
    post_comment(@agent, ids[0], 'A long time ago in a galaxy far, far away..')
    post_comment(@agent, ids[0], 'imma dinosaur  -Barack Obama')
    post_comment(@agent, ids[1], 'And one more thing..')
    merged_id = merge_articles(@agent, ids[0], ids[1])
    page = @agent.get URI.join($host, 'comments?article_id=' + merged_id)
    page.body.should include 'A long time ago in a galaxy far, far away..'
    page.body.should include 'imma dinosaur  -Barack Obama'
    page.body.should include 'And one more thing..'
  end

  it 'should only show the merge button to administrators [15 points]' do
    begin
      create_publisher(@agent, 'cs169_ag_publisher', 'aaaaaaaa')
      pub_agent = Mechanize.new
      login(pub_agent, 'cs169_ag_publisher', 'aaaaaaaa')
      article_id = create_article(pub_agent, 'Pub Blag', 'derp derp derp')

      page = pub_agent.get URI.join($host, 'admin/content/edit/' + article_id)
      page.body.should_not include 'Merge Articles'
      page.search('[name="merge_with"]').size.should == 0

      page = @agent.get URI.join($host, 'admin/content/edit/' + article_id)
      page.body.should include 'Merge Articles'
      page.search('[name="merge_with"]').size.should == 1
    ensure
      clean_autograder_publisher(@agent)
    end
  end

  it 'should only allow administrators to merge articles [15 points]' do
    begin
      create_publisher(@agent, 'cs169_ag_publisher', 'aaaaaaaa')
      pub_agent = Mechanize.new
      login(pub_agent, 'cs169_ag_publisher', 'aaaaaaaa')

      ids = [create_article(pub_agent,
                            'Blag Post A',
                            'Derp derp derp derp 12344321'),
             create_article(pub_agent,
                            'Blag Post B',
                            'Lorem ipsum dolor sit amet')]
      page = pub_agent.get URI.join($host, 'admin/content/edit/' + ids[0])
      page.forms.each do |f|
        f['merge_with'] = ids[1]
        pub_agent.submit f
      end
      # Locate the merged article
      page = @agent.get URI.join($host, 'admin/content')
      page.links_with(:text => /\[CS169 Autograder\]/).size.should == 2
    ensure
      clean_autograder_publisher(@agent)
    end
  end
end

