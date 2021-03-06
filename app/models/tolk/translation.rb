module Tolk
  class Translation < ActiveRecord::Base
    self.table_name = "tolk_translations"

    scope :containing_text, lambda {|query| where("LOWER(tolk_translations.text) LIKE LOWER(?)", "%#{query}%") }
    scope :lookup, lambda {|locale, keys|
      keys = Array(keys).map! { |key| key.to_s }
      namespace = "#{keys.last}#{I18n::Backend::Flatten::FLATTEN_SEPARATOR}%"
      includes(:phrase, :locale).where(["tolk_locales.name = ? AND (tolk_phrases.key IN (?) OR LOWER(tolk_phrases.key) LIKE LOWER(?))", locale, keys, namespace])
    }

    serialize :text
    validates_presence_of :text, :if => proc {|r| r.primary.blank? && !r.explicit_nil }
    validate :check_matching_variables, :if => proc { |tr| tr.primary_translation.present? }

    validates_uniqueness_of :phrase_id, :scope => :locale_id

    belongs_to :phrase, :class_name => 'Tolk::Phrase'
    belongs_to :locale, :class_name => 'Tolk::Locale'
    validates_presence_of :locale_id

    attr_accessible :phrase_id, :locale_id, :text, :primary_updated, :previous_text, :locale, :phrase

    attr_accessor :force_set_primary_update
    before_save :set_primary_updated

    before_save :set_previous_text

    attr_accessor :primary
    before_validation :fix_text_type

    attr_accessor :explicit_nil
    before_validation :set_explicit_nil

    after_save do
      cached_key = "i18n-#{[locale.name, phrase.key].join(I18n.default_separator)}".gsub(/\s/, "_")
      Rails.logger.error "clean i18n cache for: #{cached_key}"
      Rails.cache.delete cached_key
      true
    end

    def up_to_date?
      not out_of_date?
    end

    def out_of_date?
      primary_updated?
    end

    def primary_translation
      @_primary_translation ||= begin
        if locale && !locale.primary?
          phrase.translations.primary
        end
      end
    end

    def text=(value)
      value = value.to_s if value.kind_of?(Fixnum)
      super unless value.to_s == text
    end

    def value
      if text.is_a?(String) && /^\d+$/.match(text)
        text.to_i
      else
        text
      end
    end

    def self.detect_variables(search_in)
      variables = case search_in
        when String then Set.new(search_in.scan(/\{\{(\w+)\}\}/).flatten + search_in.scan(/\%\{(\w+)\}/).flatten)
        when Array then search_in.inject(Set[]) { |carry, item| carry + detect_variables(item) }
        when Hash then search_in.values.inject(Set[]) { |carry, item| carry + detect_variables(item) }
        else Set[]
      end

      # delete special i18n variable used for pluralization itself (might not be used in all values of
      # the pluralization keys, but is essential to use pluralization at all)
      if search_in.is_a?(Hash) && Tolk::Locale.pluralization_data?(search_in)
        variables.delete_if {|v| v == 'count' }
      else
        variables
      end
    end

    def variables
      self.class.detect_variables(text)
    end

    def variables_match?
      self.variables == primary_translation.variables
    end

    private

    def set_explicit_nil
      if self.text == '~'
        self.text = nil
        self.explicit_nil = true
      end
    end

    def fix_text_type
      if self.text.is_a?(String) and self.text =~ /\A---/
        self.text = begin
          YAML.load(self.text.strip)
        rescue ArgumentError
          self.text
        end
      end
      true
    end

    def set_primary_updated
      self.primary_updated = self.force_set_primary_update ? true : false
      true
    end

    def set_previous_text
      self.previous_text = self.text_was if text_changed?
      true
    end

    def check_matching_variables
      unless variables_match?
        if primary_translation.variables.empty?
          self.errors.add(:variables, "The primary translation does not contain substitutions, so this should neither.")
        else
          self.errors.add(:variables, "The translation should contain the substitutions of the primary translation: (#{primary_translation.variables.to_a.join(', ')}), found (#{self.variables.to_a.join(', ')}).")
        end
      end
    end
  end
end
