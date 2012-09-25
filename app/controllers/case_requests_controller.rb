class CaseRequestsController < ApplicationController

  before_filter :require_user
  before_filter :load_case_request, :only => [:show, :edit, :update, :destroy]

  def new
    add_javascripts ['new_case_request']
    @case_request = CaseRequest.new

    respond_to do |format|
      format.html
    end
  end

  def show
    respond_to do |format|
      format.html
    end
  end

  def new
    add_javascripts ['new_case_request']
    @case_request = CaseRequest.new

    respond_to do |format|
      format.html
    end
  end

  def create
    @case_request = CaseRequest.new(params[:case_request])
    
    respond_to do |format|
      if @case_request.save
        @case_request.accepts_role!(:owner, current_user)
        @case_request.accepts_role!(:creator, current_user)
        flash[:notice] = 'Case Request was successfully created.'
        format.html { redirect_to "/case_requests/#{@case_request.id}" }
      else
        format.html { render :action => 'new' }
      end
    end
  end

  def edit
    add_javascripts ['new_case_request']
  end

  def update
    respond_to do |format|
      if @case_request.update_attributes(params[:case_request])
        flash[:notice] = "Case Request was successfully updated."
        format.html { redirect_to "/case_requests/#{@case_request.id}" }
      else
        format.html { render :action => "edit" }
      end
   end   
  end

  def destroy
    @case_request.destroy
    respond_to do |format|
      format.html { redirect_to(cases_url) }
      format.xml  { head :ok }
      format.json { render :json => {} }
    end
  end
  private

  def load_case_request
    @case_request = CaseRequest.find(params[:id])
  end

  def is_case_admin
    @is_case_admin = current_user ? current_user.is_case_admin : false
  end
end
