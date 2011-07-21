require 'rubygems'
require 'camping'
require 'camping/session'

#Configuration information is at the bottom of the file.

Camping.goes :Flog

module Flog
  include Camping::Session

  def log_info(str)
    Flog::Models::Base.f_logger.info("#{Time.now.strftime("%H:%M:%S")} #{str}")
    #puts "#{Time.now.strftime("%H:%M:%S")} #{str}"
  end
end

module Flog::Models
  class Fortune < Base; belongs_to :user; end
  class User < Base; end

  def auth_admin(render_symbol)
    unless @state.user_id.blank?
      @user = User.find @state.user_id
    end
    if @user.admin  
      render(render_symbol) 
    else
       redirect Index
    end
  end

  class CreateFlog < V 0.1
    def self.up 
      create_table :flog_fortunes, :force => true do |t|
        t.column :id,          :integer, :null => false
        t.column :rank,        :integer, :null => false
        t.column :body,        :text, :null => false
        t.column :user_id,     :integer, :null => false
        t.column :created_at,  :time
        t.column :updated_at,  :time
        t.column :lock_version, :integer, :default => 0, :null => false
      end
      create_table :flog_users, :force => true do |t|
        t.column :id,       :integer, :null => false
        t.column :username, :string
        t.column :password, :string
        t.column :admin,    :bool
        t.column :created_at, :time
        t.column :updated_at, :time
        t.column :lock_version, :integer, :default => 0, :null => false
      end
    end
  end
end

module Flog::Controllers

  class Index < R '/', '/(\d+)'
    def get (fortune_id = nil)
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      @max_fortune_id =  Fortune.find(:first, :order => "id DESC").id.to_i unless @max_fortune_id

      (fortune_id.nil? || fortune_id.to_i > @max_fortune_id) ? fortune_id = @max_fortune_id : fortune_id = fortune_id.to_i
      fortune_id = 10 if fortune_id < 10
      @fortunes = Fortune.find(:all, :limit => 10, :order => "id DESC", :conditions => ['id <= ?', fortune_id])

      @fortunes.first.id >= @max_fortune_id ? @right_offset = nil : @right_offset = @fortunes.first.id + 10
      @fortunes.last.id < 10 ? @left_offset = 10 : @left_offset = @fortunes.last.id.to_i - 1 

      @users = User.find :all unless @users
      render :index
    end
  end

  class Submitter < R '/submitter/(\d+)/(\d+)', '/submitter/(\d+)'
    def get(id, offset = 0)
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(16)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      if(offset.to_i < 0)
        offset = 0
      end
      @fortunes = Fortune.find( :all, :limit => 10, :offset => offset, :order => "id DESC", :conditions => [ "user_id = ?", id])
      @left_offset = "#{id}/#{offset.to_i + 10}"
      if(offset.to_i > 0)
        @right_offset = "#{id}/#{offset.to_i - 10}"
      else
        @right_offset = nil
      end
      @users = User.find :all unless @users
      render :submitter
    end
  end

  class Search < R '/search/(\d+)', '/search'
    def get(offset = 0)
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(16)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      if(offset.to_i < 0)
        offset = 0
      end
      search_str = @cookies.search_str  
      process_search(search_str, offset) unless search_str.nil? 
      render :search
    end

    def post 
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(16)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      offset = 0;
      # TODO implement error checking
      # errors_for @post 
      process_search(input.search_str, offset)
      render :search 
    end

    def process_search(search_str, offset)
      ary = search_str.split
      cond_clause = ""
      ary << "" if ary.size == 0
      ary.each_index do |i|
        if i == 0
          cond_clause = "body like ? "
        else
          cond_clause += "AND body like ? "
        end 
      end
      ary = ary.collect {|x| '%' + x + '%'}
      log_info("conditions => [#{cond_clause}, #{ary}]")

      @fortunes = Fortune.find( :all, :limit => 10, :offset => offset, :order => "id DESC", :conditions => [ cond_clause, *ary])

      @cookies.search_str = search_str
      if (@fortunes.size == 10)
        @left_offset = "#{offset.to_i + 10}"
        if(offset.to_i > 0)
          @right_offset = "#{offset.to_i - 10}"
        else
          @right_offset = nil
        end
      else
        @left_offset = @right_offset = nil
      end
      @users = User.find :all unless @users
    end
  end

  class Add
    def get
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      unless @state.user_id.blank?
        @user = User.find @state.user_id
        @fortune = Fortune.new
      end
      render :add
    end

    def post 
      fortune = Fortune.create :rank => input.rank, :body => input.fortune_body,
                         :user_id => @state.user_id
      redirect View, fortune
    end
  end

  class Random
    def get
      @max_fortune_id =  Fortune.find(:first, :order => "id DESC").id.to_i unless @max_fortune_id
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      rand_id = rand(@max_fortune_id)
      redirect(Index, rand_id)
    end
  end
  
  class Export
    def get
      unless @state.user_id.blank?
        @headers["Content-Type"] = "text/plain"
        @user = User.find @state.user_id
        @fortunes = Fortune.find(:all, :order => "id DESC", :conditions => [ "user_id = ?", @user.id] )
        delim = "\n%\n"
        plain_body =  delim
        @fortunes.each do |f|
          plain_body += "#{f.body} #{delim}"
        end
        @body =  plain_body 
      else
        render :to_login
      end
    end
  end

  class Admin
    def get
      unless @state.user_id.blank?
          @user = User.find @state.user_id
          @users = User.find(:all, :order => "id") 
      end
      render :admin
    end
  end

  class View < R '/view/(\d+)'
    def get fortune_id 
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      @fortune = Fortune.find fortune_id
      @right_offset = @fortune.id.to_i
      @left_offset = @fortune.id.to_i - 10
      @users = User.find :all unless @users
      render :view
    end
  end
     
  class Edit < R '/edit/(\d+)', '/edit'
    def get fortune_id 
      log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
      unless @state.user_id.blank?
        @user = User.find @state.user_id
      end
      @fortune = Fortune.find fortune_id
      render :edit
    end
   
    def post 
      @fortune = Fortune.find input.fortune_id
      @fortune.update_attributes(:rank => input.rank, :body => input.fortune_body)
      redirect(Index, @fortune.id) 
    end
  end

  class EditUser < R '/edit_user/(\d+)', '/edit_user'
    def get user_id
      @edit_user = User.find user_id 
      auth_admin(:edit_user)  
    end

    def post
      admin_bool = input.admin == 'on' ? true : false
      @edit_user = User.find input.user_id
      @edit_user.update_attributes(:username => input.username, :admin => admin_bool)
      @edit_user.update_attributes(:password => input.password) if input.password.length > 0
      @edit_user = nil
      redirect Admin
    end
  end

  class AddUser < R '/add_user'
    def get 
      auth_admin(:add_user)  
    end

    def post
      admin_bool = input.admin == 'on' ? true : false
      new_user = User.new("username" => input.username, 
                          "admin" => admin_bool,
                          "password" => input.password)
      new_user.save
      redirect Admin
    end
  end
     
 
    class ToLogin
      def get 
        render :to_login
      end
    end  
  
    class Login
      def post 
        @user = User.find :first, :conditions => ['username = ? AND password = ?', input.username, input.password]
    
        if @user
            @login = 'login success !'
            @state.user_id = @user.id
            @state.admin = @user.admin
            redirect Index 
        else
            @login = 'Wrong user name or password'
            render :login
        end
      end
    end
     
    class Logout
      def get
        @state.user_id = nil
        @state.admin = false
        @user = nil
        render :logout
      end
    end

    
    class Atom < R '/atom.xml'
      def get
        log_info("#{@env.REMOTE_ADDR.ljust(16)} #{@env.PATH_INFO.ljust(10)} #{@env.HTTP_USER_AGENT.slice!(0..80)}")
        @headers["Content-Type"] = "application/atom+xml"
        @fortunes = Fortune.find(:all, :limit => 10, :order => "id DESC")
        @users = User.find :all unless @users
          
        atom_str = %{<?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <id>fortunes.mydomain.net:3002/flog/</id>
            <title>Flog Feed</title> 
            <link href="http://fortunes.mydomain.net:3002/flog/atom.xml" rel="self"/>
            <updated>#{Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")}</updated>
            <author> 
              <name>Chuck Fouts</name>
              <email>chuck+flog@mydomain.net:3002</email>
            </author> 
        }
        f_ary = @fortunes.collect do |f|
          un = ""
          @users.each {|x| un = x.username if(f.user_id == x.id) }
          %{
            <entry>
              <title> Fortune ##{f.id} </title> 
              <id>http://fortunes.mydomain.net:3002/flog/#{f.id}</id>
              <link href="http://fortunes.mydomain.net:3002/flog/#{f.id}"/>
              <updated>#{f.created_at.strftime("%Y-%m-%dT%H:%M:%SZ")}</updated>
              <author><name>#{un}</name></author>
              <content type="html">
                <![CDATA[ #{pre f.body}]]>
              </content>
            </entry>
          }
        end
        atom_str += f_ary.to_s

        @body = atom_str + "</feed>"
      end
    end

    class Style < R '/styles.css'
      def get
        @headers["Content-Type"] = "text/css; charset=utf-8"
        @body = %{
            body {
              margin: 0;
              padding: 0;
              background-color:#182801;
              color: #fff;
              font-family: Verdana, Helvetica, sans-serif;
              font-size: 95%;
            }

            div.content {
              padding: 20px;
              margin: 0;
            }

            .top_row {   }
            .nav {
              float: left;
              margin-top: 5px;
            }
            .search {
              float: right;
              margin: 0;
              padding: 0;
              border: 0;
              height: 27px;
            }

            .search fieldset {
              margin: 0;
              padding: 0;
              border: 0;
            }

            .fortune {
              padding: 12px 12px 0 12px;
              background-color: #7A9431;
              border: 1px dotted;
            }

            .quotebox {
              width: 510px; padding: 0;
              margin: 0 auto 15px;  
              background-color: #ccdd9f;
              color: #222; border: solid 1px #182801;
            }

            .quote-header {
              font-size: 95%;
              padding: .2em 1.2em .2em 1.2em;
              margin: 0;
              background-color:#182801;
              color: #fff;
            }

            .quotee {
              float: left;
            }
               
            .quote-number {
              float: right;
            }
               
            .quote {
              padding: 1.2em 1.2em 0 1.2em;
            }
            
            .spacer {
              clear: both;
              padding: 0;
              margin: 0;
            }

            a, a:link {color: #fff; text-decoration: none;}
            a:visited {color: #fff;}
            a:hover {color: #ff6633; text-decoration: underline;}


            .nav ul {
              margin-left: 0;
              padding-left: 0;
              display: inline;
              font-size: 95%;
            } 
            
            .nav ul li {
              margin-left: 0;
              padding: 0 10px 0 12px;
              border: 0;
              list-style: none;
              display: inline;
            }
               
            .first ul li {
              margin-left: 0;
              padding-left: 0;
              border: 0;
              list-style: none;
              display: inline;
            }
            
           .quote p {
              padding: 0 0 1.2em 0;
              margin: 0;
              font-size: 95%;
              font-family: Andale, monospace;
              line-height: 1.5em;
            }


            div.fortune.form { width: 20%; }

            ul.errors {color:red; font-weight:bold;} 
            .td_display {
                padding: 0;
                margin: 0;
                background-color: #CCDD9F;
                color: #222
            }

            h1.header {
              margin: 0; 
              padding: 0;
            }

            pre {
             	padding: .2em .2em 0 .5em;
                font-size: 95%;
             	font-family: Andale, monospace;
                line-height: 1.5em;
            }
            .fi_display {
                font-size: 95%;
             	padding: .2em .2em 0 .5em;
                margin: 0;
                background-color:#182801;
                color: #fff
            }



        }
      end
    end
end


module Flog::Views

  def layout
    html do
      head do
        title 'flog'
        link :rel => 'stylesheet', :type => 'text/css', 
             :href => '/styles.css', :media => 'screen'
      end
      body do
        h1.header { 
        }
        div.content do
          self << yield
        end
      end
    end
  end

  def index
    _nav(@left_offset, @right_offset, Index)
    if @fortunes.empty?
      p 'No fortunes found.'
      p { a 'Add', :href => R(Add) }
    else
      _display_fortunes(@fortunes)
    end
    _nav(@left_offset, @right_offset, Index)
    br
    br
  end

  def submitter
    _nav(@left_offset, @right_offset, Submitter)
    _display_fortunes(@fortunes)
    _nav(@left_offset, @right_offset, Submitter)
    br
    br
  end

  def search
    _nav(@left_offset, @right_offset, Search)
    _display_fortunes(@fortunes)
    _nav(@left_offset, @right_offset, Search)
    br
    br
  end

  def login
    div.fortune.form {
      p { b @login }
      p { a 'Continue >>', :href => R(Index) }
    }
  end

  def logout
    div.fortune.form {
      p "You have been logged out."
      p { a 'Continue >>', :href => R(Index) }
    }
  end

  def to_login
    _login
  end

  def add
    if @user
      div.fortune {  
        _form(fortune, :action => R(Add))
      }
    else
      _login
    end
  end

  def admin
    if @user && @user.admin
      _admin
    else
      _login
    end
  end


  def edit
    if((@state.user_id == fortune.user_id) || @state.admin)
      _nav(fortune.id, fortune.id, Index)
      div.fortune {  
        _form(fortune, :action => R(Edit))
      }
      _nav(fortune.id, fortune.id, Index)
    else
      _login
    end
  end

  def edit_user
    if @user.admin
      _edit_user(@edit_user)
    end
  end

  def add_user
    if @user.admin
      _add_user
    end
  end


  def view
    _nav(@left_offset, @right_offset, Index)
    div.fortune {
      table(:border => '0', :cellspacing =>'0' ) {
        _fortune(fortune)
      }
    }
    _nav(@left_offset, @right_offset, Index)
  end

  # partials
  def _login
    div.fortune.form {
      form(:action => R(Login), :method => 'post') {
        label 'Username', :for => 'username'; br
        input :name => 'username', :type => 'text'; br

        label 'Password', :for => 'password'; br
        input :name => 'password', :type => 'password'; br
        br
        input :type => 'submit', :name => 'login', :value => 'Login'
      } 
    }
  end

  def _admin
    _nav(nil, nil, Index)
    div.fortune {
      self << "Administration"
      br
      br
      a "Add User", :href => R(AddUser)
      br
      br
      self << "Edit User"
      table(:width => '860', :border => '1', :cellpadding =>'2', :style => 'color:#181818;') {
        tr {
          th{ "User Name" }
          th{ "User Id" }
          th{ "Admin" }
          th{ "Created At" }
          th{ "Updated At" }
        }
        @users.each do |x| 
        tr {
            td { a "#{x.username}", :href => R(EditUser, x) } 
            td { x.id  } 
            td { x.admin }
            td { _date(x.created_at) } 
            td { _date(x.updated_at) }
        }
        end
      }
    }
    _nav(nil, nil, Index)
  end

  
  def _edit_user(user)
    div.fortune.form {
      self << "Id: #{user.id} " 
      br
      br
      form(:action => R(EditUser), :method => 'post') {
        input :type => 'hidden', :name => 'user_id', :value => "#{user.id}"

        label 'Admin', :for => 'admin'; 
        if(user.admin)
          input(:name => 'admin', :type => 'checkbox', :checked => 'on'); br
        else
          input(:name => 'admin', :type => 'checkbox'); br
        end
        label 'Username', :for => 'username'; br
        input :name => 'username', :type => 'text', :value => user.username; br
        br
        label 'Password', :for => 'password'; br
        input :name => 'password', :type => 'password'; br
        br
        input :type => 'submit', :name => 'edit_user', :value => 'Edit User'
      } 
    }

  end

  def _add_user
    div.fortune.form {
      br
      form(:action => R(AddUser), :method => 'post') {
        label('Admin', :for => 'admin'); 
        input(:name => 'admin', :type => 'checkbox'); br
        br
        label('Username', :for => 'username'); br
        input(:name => 'username', :type => 'text'); br
        br
        label('Password', :for => 'password'); br
        input(:name => 'password', :type => 'password'); br
        br
        input :type => 'submit', :name => 'add_user', :value => 'Add User'
      } 
    }

  end



  def _display_fortunes(d_fortunes)
    div.fortune {
      table(:border => '0', :cellspacing =>'0' ) {
       for fortune in d_fortunes
         _fortune(fortune)
       end
      }
    }
  end
  
  def _fortune(fortune)
      tr {
        td.fi_display(){ 
          a _get_username(fortune.user_id), :href => R(Submitter, fortune.user_id) 
          self << "&nbsp;"
          self << _date(fortune.created_at)
        }
        td.fi_display() { 
          if(@state.user_id == fortune.user_id || @state.admin)
            self << "#{a fortune.id, :href => R(View, fortune)} "
            self << "&nbsp;&nbsp;"
            a 'Edit', :href => R(Edit, fortune)
          else
            "#{a fortune.id, :href => R(View, fortune)} "
          end
        } 
      }
      tr {
        td.td_display(:colspan => '2' ) {
          pre "#{fortune.body}", :width => '90'
        }
      }
      tr { td {"&nbsp;"}}
  end

  def _date(time)
    time.strftime("%b %d %Y")
  end

  def _nav(left, right, forward_page)
   div.spacer {'&nbsp;'}
   div.top_row {
    div.nav {
      ul.nav {
          li { a('<<', :href => R(forward_page, left)) } if left  
          li { a('oldest', :href => R(Index, 10)) } if left 
          if @state.user_id 
            li { a('add', :href => R(Add)) } unless @state.user_id.blank? 
            li { a('admin', :href => R(Admin)) } if !@state.user_id.blank? && @state.admin
            li { a('logout', :href => R(Logout))} 
          else
            li { a("login", :href => R(ToLogin) ) }
          end
          li { a('main', :href => R(Index)) } if right || (!right && !left) 
          li { a('random', :href => R(Random)) } 
          li { a('>>', :href => R(forward_page, right)) } if right
          li { "&nbsp;" }
          li { a 'flog', :href => 'http://sackheads.org/~kheldar/power.html' }
        }
      }
      div.search {
        div.fieldset {
          form(:action => R(Search), :method => 'post') { 
             input(:name => 'search_str', :type => 'text') 
             input(:type => 'submit', :name => 'search', :value => 'Search') 
          }
        }
      }
      div.spacer {}
   }
  end


  def _get_username(uid)
    un = @users[0]
    @users.each {|x| un = x.username if(uid == x.id) }
    un
  end

  def _form(fortune, opts)
    p { 
      text "You are logged in as #{@user.username} | "
      a 'Logout', :href => R(Logout)
    } 
    form({:method => 'post'}.merge(opts)) { 
      input :type => 'hidden', :name => 'fortune_id', :value => fortune.id
      input :type => 'hidden', :name => 'rank', :value => '0' 
      label 'Fortune', :for => 'fortune_body' 
      br
      br
      textarea fortune.body, :cols => '80', :rows => '20', :name => 'fortune_body'#, :wrap => 'soft'
      br
      br
      input(:type => 'submit', :value => 'Submit')
    }
  end
end


def Flog.create
  Camping::Models::Session.create_schema
  unless Flog::Models::Fortune.table_exists?
    Flog::Models.create_schema
  end
end

if __FILE__ == $0
  require 'mongrel/camping'

  class Flog::Models::Base
    cattr_accessor :f_logger
  end

  Flog::Models::Base.establish_connection :adapter => 'postgresql',
     :database => 'fortunes',
     :username => 'username'
     :password => 'password'

  Flog::Models::Base.logger = Logger.new('camping.log')
  Flog::Models::Base.f_logger = Logger.new('flog.log')
  Flog::Models::Base.default_timezone = :utc
  Flog.create

  # Use the Configurator as an example rather than Mongrel::Camping.start
  #config = Mongrel::Configurator.new :host => "0.0.0.0" do
  #  listener :port => 3002 do
  #    uri "/flog", :handler => Mongrel::Camping::CampingHandler.new(Flog)
  #    uri "/favicon", :handler => Mongrel::Error404Handler.new("")
  #    trap("INT") { stop }
  #    run
  #  end
  #end
  
  # Use IP of interface you want Mongrel to use instead of "0.0.0.0".
  # Replace any occurance of "mydomain" with your domain.  Mainly for the atom feed.
  # Replace 'username' and 'password' with your creds for db connection 
  server = Mongrel::Camping::start("0.0.0.0", 3002, "/flog", Flog)
  puts "** Flog is running at http://localhost:3002/flog"
  server.run.join

  Flog::Models::Base.f_logger.info("******** START FLOG *****#{Time.now}")
end
