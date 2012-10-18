module Tolk
  class LocalesController < Tolk::ApplicationController
    before_filter :find_locale, :only => [:show, :all, :update, :updated]
    # before_filter :ensure_no_primary_locale, :only => [:all, :update, :show, :updated]

    def index
      @locales = Tolk::Locale.secondary_locales.sort_by(&:language_name)
    end

    def update
      @locale.translations_attributes = params[:translations]
      @locale.save
      redirect_to request.referrer
    end
  end
end
