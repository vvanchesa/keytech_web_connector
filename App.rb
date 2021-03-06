## Remember to run 'bundle install' if something in Gemfile has changed!
## To start the app run 'rackup ' instead of 'ruby kt.rb' !

require 'rubygems'
require 'bundler'
require 'sinatra/base'
require 'sinatra/contrib/all'
require 'sinatra/cross_origin'

require 'sprockets'
require 'rack-flash'
require 'rack/flash/test'
require 'filesize'
require 'dalli'
require 'memcachier'
require 'rack/session/dalli'
require 'rack-cache'

#
require './classes/UserAccount'
require './classes/PasswordRecoveryList'


class App < Sinatra::Base

set :root, File.dirname(__FILE__)

  register Sinatra::Contrib
  register Sinatra::CrossOrigin

  require_relative "helpers/KtApi"
  require_relative "helpers/DetailsHelper"
  require_relative "helpers/SearchHelper"
  require_relative "helpers/ApplicationHelper"
  require_relative "helpers/SessionHelper"
  require_relative "helpers/MailSendHelper"

  # Enable flash messages
  use Rack::Flash, :sweep => true

  helpers do
    def flash_types
      [:success, :notice, :warning, :error]
    end
  end

  #include Helpers module
  helpers ApplicationHelper
  helpers SearchHelper
  helpers SessionHelper
  helpers Sinatra::KtApiHelper
  helpers DetailsHelper
  helpers MailSendHelper

  #Some configurations

  configure do

    # Set up Memcache
    dalliOptions={:expires_in =>1800} #30 minuten
    set :cache, Dalli::Client.new(nil,dalliOptions)

    #enable sessions, for 900 seconds (15 minutes)
    use Rack::Session::Cookie,
      :expire_after => 2592000,
      :key => 'rack.session',
      :path => "/",
      :secret => ENV['COOCKIE_SECRET']
  end


  configure :development do

    # at Development SQLlite will do fine

    DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/development.db")

    # Mail Send
    Mail.defaults do
      if ENV['MAILSSL'] == "TRUE"
        delivery_method :smtp, { :address              => ENV['MAILSERVER'] || "smtp.gmail.com",
                                 :port                 => 587,
                                 :user_name            => ENV['MAILUSERNAME'] || "<MailUsername>",
                                 :password             => ENV['MAILPASSWORD'] || "<MAILPassword>",
                                 :authentication       => :plain,
                                 :enable_starttls_auto => true  }
      else
        puts "MAILSERVER - NO SSL"
      delivery_method :smtp, { :address              => ENV['MAILSERVER'] || "smtp.gmail.com",
                                 :port                 => 587,
                                 :user_name            => ENV['MAILUSERNAME'] || "<MailUsername>",
                                 :password             => ENV['MAILPASSWORD'] || "<MailUsername>"
                                  }
      end

    end

  end



  #Some configurations
  configure :production do
    require 'dm-postgres-adapter'

    # Catch internal errors and redicert
    set :raise_errors, false
    set :show_exceptions, false
    error do
      redirect to('/')
    end

    # A Postgres connection:
    DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/mydb')
    # TODO: Payments als Production Code einbauen

    #  Mail Send
    Mail.defaults do
      delivery_method :smtp, { :address              => "smtp.sendgrid.net",
                               :port                 => 587,
                               :user_name            => ENV['SENDGRID_USERNAME'],
                               :password             => ENV['SENDGRID_PASSWORD'],
                               :authentication       => :plain,
                               :enable_starttls_auto => true  }
    end
  end

  DataMapper.auto_upgrade!

  # Assets (Cleard)
  set :environment, Sprockets::Environment.new
  environment.append_path "assets/stylesheets"
  environment.append_path "assets/javascripts"
  environment.append_path "assets/images"
  #environment.js_compressor = :uglify
  #environment.css_compressor = :scss


  enable :method_override


  # Routes
  # These are your Controllers! Can be outsourced to own files but I leave them here for now.

  # handle 404 error
  not_found do
    status 404
    erb :oops
  end

  get '/assets/*' do
    env["PATH_INFO"].sub!("/assets","")
    settings.environment.call(env)
  end

  # main page controller
  get '/' do
    if session[:user]
      erb :overview
    else

      #Never logged in, show the normal index / login page
      erb :login
    end
  end


  # redirects to a search page and fill search Data, parameter q is needed
  get '/search' do
    if currentUser
      if currentUser.usesDemoAPI? || currentUser.hasValidSubscription?

        @result= findElements(params[:q])
        erb :search
      else
        flash[:warning] = "You need a valid subscription to use a API other than the demo API. Go to the account page and check your current subscription under the 'Billing' area."
        erb :search
      end

    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

  #new User signup page
  get '/signup' do
     #flash[:error] = "Signup any new accounts not available"
    #redirect '/'
    #return
    erb :signup
  end

  # Signup a new user, take POST arguments and try to create a new useraccount
  # flash message if something goes wrong
  post '/signup' do

     @user = UserAccount.new(
                :email => params[:email].downcase,
                :fullname => params[:fullname],
                :password => params[:password], :password_confirmation => params[:password_confirmation],
                :keytechUserName =>params[:keytech_username],
                :keytechPassword => params[:keytech_password],
                :keytechAPIURL => params[:keytech_APIURL].downcase)
        if @user.save

          sendNewSignUpMail(@user)

          if UserAccount.hasKeytechAccess(@user)
            # OK, Access granted by API
            session[:user] = @user.id
            redirect '/'
          else
            flash[:warning] = "User access denied by keytech API."
          end
        else

          flash[:error] = @user.errors.full_messages
          redirect '/signup'
        end
  end

  get '/account' do
    # Allow cross domains (for testing keytech APIs)
    cross_origin
    # Shows an edit page for current account
    @user = currentUser
    if @user

      #if params[:action].eql? "cancelPlan"
      #  print "Cancel Plan"
      #    # Cancel current subscription
      #    Braintree::Subscription.cancel(@user.subscriptionID)
      #
      #    @user.subscriptionID = ""  # Remove subscriptionID
      #    @user.save
      #    redirect '/account'
      #    return
      #end

      # if params[:action].eql? "startPlan"
      #   print "Start Plan"
      #     # Start a new subscription. (Now without any trials)
      #     customer = Braintree::Customer.find(@user.billingID)
      #     if customer
      #         payment_method_token = customer.credit_cards[0].token

      #         result = Braintree::Subscription.create(
      #                   :payment_method_token => payment_method_token,
      #                   :plan_id => "silver_plan",
      #                   :options => {
      #                     :start_immediately => true # A recreated plan does not have a trial period
      #                   }
      #                 )

      #         @user.subscriptionID = result.subscription.id  # Add subscriptionID
      #         @user.save
      #         redirect '/account'

      #     else
      #       # Customer with this ID not found - remove from Customer
      #       @user.billingID = 0
      #       @user.save

      #       flash[:error] = "No customer record found. Please try again."
      #       redirect '/account'
      #     end
      # end

    erb :account

    else
      redirect '/'
    end
  end

  post '/account' do
    user = currentUser
    if user
      puts "Submittype:" + params[:submit]

      if params[:submit] == "commitKeytechCredentials"
        puts "Save credentials"
        user.keytechAPIURL = params[:keytechAPIURL]
        user.keytechPassword = params[:keytechPassword]
        user.keytechUserName = params[:keytechUserName]

        if !user.save
          flash[:warning] = user.errors.full_messages
        else
          puts "Save OK"
        end
      end

      if params[:submit] == "commitProfile"
        puts "Update profile"
        user.fullname = params[:fullname]

        if !user.save
          flash[:warning] = user.errors.full_messages
        else
          puts "Save OK"
        end

      end

      if params[:submit] =="commitPassword"
        # Check for current Password
        if !params[:current_password]
          flash[:error] = "Password was empty"
          redirect '/account'
        end

        authUser =  UserAccount.authenticate(user.email, params[:current_password])
        if authUser
          password = params[:password]
          password_confirmation = params[:password_confirmation]

          if password.empty? && password_confirmation.empty?
              flash[:warning] = "New password can not be empty"
              redirect '/account'
          end

          if password.eql? password_confirmation
            user.password = password
            user.password_confirmation = password_confirmation
            if !user.save
              flash[:error] = user.errors.full_messages
            end
          else
            flash[:error] = "Password and password confirmation did not match."
          end

        else
          flash[:error] = "Current password is invalid"
        end
      end

    else
      puts "No user found!"
    end

    # Return to account site
    redirect '/account'
  end

  # Sets a credit card for current logged in user
  get '/account/subscription' do

    @user = currentUser

    if @user
        if !@user.subscriptionID.empty?
          # A billing customer is already given
          # TODO: Eine Subscription kann gesetzt sein, auf 'Aktiv' - Status prüfen
          erb :showBillingPlan
        else
          erb :customerAccount
        end

    else
        redirect '/'
    end
  end

# For Payment Data
  post '/account/subscription' do
    result = Braintree::Customer.create(
      :first_name => params[:first_name],
      :last_name => params[:last_name],
      :credit_card => {
        :billing_address => {
          :postal_code => params[:postal_code]

        },
        :number => params[:number],
        :expiration_month => params[:month],
        :expiration_year => params[:year],
        :cvv => params[:cvv]
      }
    )
    if result.success?
      "<h1>Customer created with name: #{result.customer.first_name} #{result.customer.last_name}</h1>"

      currentUser.billingID = result.customer.id

      # Start the plan
      customer = result.customer
      payment_method_token = customer.credit_cards[0].token

      result = Braintree::Subscription.create(
        :payment_method_token => payment_method_token,
        :plan_id => "silver_plan" # This is teh default monthly plan
      )

      if result.success?
        "<h1>Subscription Status #{result.subscription.status} </h1>"
      else
        flash[:error] = result.message
        redirect '/create_customer'
      end
    else

      # Something goes wrong
      flash[:error] = result.message
      redirect '/create_customer'
    end
  end

  # Login controller
  post '/login' do

    user = UserAccount.authenticate(params[:username].downcase,params[:password])

    if user
      session[:user] = user.id
      redirect '/'
    else
      flash[:error] = invalidUserNameOrPasswordText
      redirect '/'
    end
  end

  get '/logout' do
    session.destroy

    flash[:notice] = "You have logged out."
    redirect '/'
  end

  get '/account/forgotpassword' do
    erb :"passwordManagement/forgotpassword"
  end

    # Send a password recovery link
  post '/account/forgotpassword' do
    # existiert diese Mail- Adrese ?

    if params[:email].empty?
      flash[:warning] = "Enter a valid mail address"
      redirect '/account/forgotpassword'
      return
    end

    # Get user account by its mail
    user = UserAccount.first(:email => params[:email].to_s.downcase)

    if !user
      flash[:warning] = "This email address is unknown. Please enter a valid useraccount identified by it's email"
      redirect '/account/forgotpassword'
      return
    end

    # Delete all old password recoveries based in this email
    PasswordRecoveryList.all(:email => params[:email]).destroy

    # Generate a new password recovery pending entry
    newRecovery = PasswordRecoveryList.create(:email=> params[:email] )
    # Now send a mail
    if newRecovery
      sendPasswordRecoveryMail(newRecovery)
      flash[:notice] = "A recovery mail was send to #{params[:email]} please check your inbox."
      erb :"passwordManagement/recoveryMailSent"
    end
  end

  # Recovers lost password,if recoveryID is still valid in database
  get '/account/password/reset/:recoveryID' do
    if params[:recoveryID]
      # recovery Token exist?
      recovery = PasswordRecoveryList.first(:recoveryID => params[:recoveryID])
      print "Recovery: #{recovery}"

      if recovery
        if !recovery.isValid?
          recovery.destroy
          flash[:warning] = "Recovery token has expired"
          return erb :"passwordManagement/invalidPasswordRecovery"
        end

        @user = UserAccount.first(:email => recovery.email.to_s)
        if @user
          print " Recovery: User account found!"

          # Start a new password, if useraccount matches
          erb :"passwordManagement/newPassword"
        else
          flash[:warning] = "Can not recover a password from a deleted or disabled useraccount."
          erb :"passwordManagement/invalidPasswordRecovery"
        end

      else
        flash[:warning] = "Recovery token not found or invalid"
        erb :"passwordManagement/invalidPasswordRecovery"
      end
    else
      flash[:warning] = "Invalid page - a recovery token is missing."
      erb :"passwordManagement/invalidPasswordRecovery"
    end
  end

  # accepts a new password and assigns it to current user
  post '/account/password/reset' do
    recovery = PasswordRecoveryList.first(:recoveryID => params[:recoveryID])
    if recovery
        user = UserAccount.first(:email => recovery.email.to_s)
        if user
            # Password check and store it
            password = params[:password]
            password_confirmation = params[:password_confirmation]

            if password.empty? && password_confirmation.empty?
                flash[:warning] = "New password can not be empty"
                redirect '/account/password/reset/#{params[:recoveryID]}'
            end

            if password.eql? password_confirmation
              user.password = password
              user.password_confirmation = password_confirmation
              if !user.save
                flash[:error] = user.errors.full_messages
              else
                # Everything is OK now
                print " Password reset: OK!"
                recovery.destroy
                flash[:notice] = "Your new password was accepted. Login now with you new password."
                redirect '/'
              end
            else
              flash[:error] = "Password and password confirmation did not match."
              redirect '/account/password/reset/#{params[:recoveryID]}'
            end
        end
    end
  end

  # Presents a view for a specific element
  get '/elementdetails/:elementKey' do
    if currentUser

      @element = loadElement(params[:elementKey])
      @detailsLink = "/elementdetails/#{params[:elementKey]}"
      @viewType = params[:viewType]

      erb :elementdetails
    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

  # Loads Element data
  get '/elementdata/:elementKey' do
    if currentUser
        data = loadElement(params[:elementKey],'ALL')
        return data.to_json
    end
  end

    # Loads the admin console
  get '/admin' do
    if loggedIn? && currentUser.isAdmin?
      @users=UserAccount.all
      erb :admin
    else
      flash[:notice] = "You are not logged in."
      redirect '/'
    end
  end

    # Delets a useraccount
  delete '/admin/:email' do
    user = UserAccount.first(:email => recovery.email.to_s)
    if user.email.eql currentuser.email
      flash[:danger] = 'Can not delete yourself'
      return
    end

    if user.delete
      flash[:info] = 'Useraccount deleted'
      redirect '/admin'
    else
      flash[:warning] = 'Failed deleting UserAccount'
      redirect '/admin'
    end
  end

 # Redirected when 'submit' is clicked
  post '/contact' do
    name= params[:name]
    email= params[:email]
    message= params[:message]

    mail = Mail.new do
      from    name + "<" + email + ">"
      to      'support@claus-software.de'
      subject name + " has contacted you"
      body    message
    end

    if mail.deliver!
      flash[:notice] = "Mail was sent. Thank you."
    else
      print "Error sending mail"
      flash[:notice] = "Error sending mail"
    end
    redirect '/support'
  end

    # Redirection for file download

  # Image forwarding. Redirect classimages provided by API to another image directly fetched by API
  get '/classes/:classKey/smallimage' do
    if loggedIn?
      cache_control :public, max_age: 1800
      content_type "image/png"
      loadClassImage(params[:classKey])
    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

# Loads the element thumbnail
  get '/element/:thumbnailHint/thumbnail' do
    if loggedIn?
      puts "Load a thumbnail"
      cache_control :public, max_age:1800
      content_type "image/png"
      loadElementThumbnail(params[:thumbnailHint])
    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

get '/files/:elementKey/masterfile' do
    if loggedIn?
      content_type "application/octet-stream"

      loadMasterfile(params[:elementKey])
    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

  get '/files/:elementKey/files/:fileID' do
    if loggedIn?
      content_type "application/octet-stream"

      loadFile(params[:elementKey],params[:fileID])
    else
      flash[:notice] = sessionInvalidText
      redirect '/'
    end
  end

  # Static Pages
   # Loads the static page support
  get '/support' do
     cache_control :public, max_age: 1800
     erb :"public/support"
  end

  get '/terms' do
    cache_control :public, max_age: 1800
    erb :"public/terms"
  end

  get '/impressum' do
    cache_control :public, max_age: 1800
    erb :"public/impressum"
  end

  get '/features' do
    cache_control :public, max_age: 1800
    erb :"public/features"
  end

  get '/pricing' do
    cache_control :public, max_age: 1800
    erb :"public/pricing"
  end

  get '/debug' do
    session.inspect
  end

end
