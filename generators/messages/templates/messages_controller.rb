class MessagesController < ApplicationController
  
  include RestfulEasyMessagesControllerSystem
  
  # Restful_authentication Filter
  before_filter :rezm_login_required

  # GET /messages
  def index
    redirect_to inbox_messages_url
  end
  
  # GET /messages/1
  def show
    @message = Message.find_by_id(params[:id])
    
    respond_to do |format|
      if can_view(@message)
        @message.mark_message_read(rezm_user)
        format.html # show.html.erb
      else
        headers["Status"] = "Forbidden"
        format.html {render :file => "public/403.html", :status => 403}
      end
    end
  end
  
  # GET /messages/new
  def new
    @message= Message.new
  end

  # POST /messages
  def create
    @message = Message.new((params[:message] || {}).merge(:sender => rezm_user))
    
    respond_to do |format|
      if @message.save
        flash[:notice] = 'Message was sent successfully.'
        format.html { redirect_to outbox_messages_path }
      else
        format.html { render :action => "new" }
      end
    end
  end
  
  # DELETE /messages/1
  def destroy
    @message= Message.find_by_id(params[:id])
    
    respond_to do |format|
      if can_view(@message)
        mark_message_for_destruction(@message)
        format.html { redirect_to current_mailbox }
      else
        headers["Status"] = "Forbidden"
        format.html {render :file => "public/403.html", :status => 403}
      end
    end
  end
  
  ### Non-CRUD Actions
  
  # GET /messages/inbox
  # GET /messages/inbox.xml
  # GET /messages/inbox.atom
  # Displays all new and read and undeleted messages in the User's inbox
  def inbox
    session[:mail_box] = "inbox"
    @messages = rezm_user.inbox_messages
    respond_to do |format|
      format.html { render :action => "index" }
      format.xml  { render :xml    => @messages.to_xml }
      format.atom { render :action => "index", :layout => false }
    end
  end
  
  # GET /messages/outbox
  # Displays all messages sent by the user
  def outbox
    session[:mail_box] = "outbox"
    @messages = rezm_user.outbox_messages
    
    respond_to do |format|
      format.html { render :action => "index" }
    end
  end
  
  # GET /messages/trashbin
  # Displays all messages deleted from the user's inbox
  def trashbin
    session[:mail_box] = "trashbin"
    @messages = rezm_user.trashbin_messages
    
    respond_to do |format|
      format.html { render :action => "index" }
    end
  end
  
  # GET /messages/1/reply
  def reply
    replied_message = Message.find(params[:id])
    @message = Message.new
    
    respond_to do |format|
      if can_view(replied_message)
        @message.recipient = replied_message.sender_name
        @message.subject = "Re: " + replied_message.subject 
        @message.body = "\n\n___________________________\n" + replied_message.sender_name + " wrote:\n\n" + replied_message.body
        format.html { render :action => "new" }
      else
        headers["Status"] = "Forbidden"
        format.html {render :file => "public/403.html", :status => 403}
      end
    end
  end
  
  # POST /messages/destroy_selected
  def destroy_selected
  
    respond_to do |format|
      if !params[:to_delete].nil?
        messages = params[:to_delete].map { |m| Message.find_by_id(m) } 
        messages.each do |message| 
          mark_message_for_destruction(message)
        end
        format.html { redirect_to current_mailbox }
      else
        format.html { redirect_to inbox_messages_path }
      end
    end
  end
  
  protected
          
  # Security check to make sure the requesting user is either the 
  # sender (for outbox display) or the receiver (for inbox or trash_bin display)
  def can_view(message)
    true if !message.nil? and (rezm_user.id == message.sender_id or rezm_user.id == message.receiver_id)
  end
  
  def current_mailbox
    case session[:mail_box]
    when "inbox"
      inbox_messages_path
    when "outbox"
      outbox_messages_path
    when "trashbin"
      trashbin_messages_path
    else
      inbox_messages_path
    end
  end
  
  # Performs a "soft" delete of a message then check if it can do a destroy on the message
  # * Marks Inbox messages as "receiver deleted" essentially moving the message to the Trash Bin
  # * Marks Outbox messages as "sender_deleted" and "purged" removing the message from [:inbox_messages, :outbox_messages, :trashbin_messages]
  # * Marks Trash Bin messages as "receiver purged"
  # * Checks to see if both the sender and reciever have purged the message.  If so, the message record is destroyed
  #
  # Returns to the updated view of the current "mailbox"
  def mark_message_for_destruction(message)
    if can_view(message)
      
      # "inbox"
      if rezm_user.id == message.receiver_id and !message.receiver_deleted
        message.receiver_deleted = true             
        message.mark_message_read(rezm_user)
      # "outbox"
      elsif rezm_user.id == message.sender_id
        message.sender_deleted = true
        message.sender_purged = true
            
      # "trash_bin"
      elsif rezm_user.id == message.receiver_id and message.receiver_deleted
        message.receiver_purged = true
      end
      
      message.save(false) 
      message.purge
    end
  end  
end
