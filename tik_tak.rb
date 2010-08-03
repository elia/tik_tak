# Copyright (c) 2009 Elia Schito
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'tk'
require 'active_support/core_ext'
Thread.abort_on_exception = true

class ::TkFileLabel < Tk::Label
  attr_accessor :default_text
  def reset
    self.text default_text || ""
  end
end

module TikTak
  VERSION = '1.1'
  
  attr_reader :parent
  
  # %w[text].each do |widget|
  #   module_eval "def #{widget}(*args, &block) add(Tk#{widget.capitalize}, *args, &block) end\n"
  # end
  
  def method_missing name, *args, &block
    klass = "Tk#{name.to_s.classify}"
    widget = Object.const_get(klass)
    add widget, *args, &block
  rescue NoMethodError
    puts "Class #{klass} not found, passing to default \"method missing\"."
    super
  end
  
  def button(name, label = nil, options = nil, &block)
    label ||= name.to_s.capitalize
    add(TkButton, name, (options || {}).update( :command => block,
                                        :text => label,
                                        :pack => nil ))
  end
  
  def open_file_button name, text = nil, options = {}, &block
    text ||= name.to_s.humanize
    
    bind_options, dialog_options, label_options = options.delete(:bind), options.delete(:dialog), options.delete(:label)
    
    label_name = "#{name}_label"
    button(name, "#{text} file...", options).pack(:side => :left)
    
    file_label(label_name).pack(:side => :left)
    default_label_text = "Click to load the #{text} file..."
    gui[label_name].configure( {:text => default_label_text,
                                :width => default_label_text.size,
                                :justify => :left }.merge(label_options || {}) )
    
    gui[label_name].default_text = default_label_text
    
    bind_command(name, bind_options) { disable_elements_while(name) {
      file_path = Tk.getOpenFile({:title => "Select the #{text} file..."}.update(dialog_options || {}))
      unless file_path.blank?
        file_path = File.expand_path(file_path)
        block.call(file_path)
        gui[label_name].text File.basename(file_path)
      else
        block.call(nil)
        gui[label_name].reset #text default_label_text
      end
    }}
  end
  
  
  def label(name, label = nil, options = {})
    label ||= name.to_s.capitalize
    add(TkLabel, name, options.update(:text => label,
                                      :pack => nil))
  end
  
  def frame name = nil, options = {}, &block
    current_frame = add(TkFrame, name, options)
    with_parent(current_frame, &block) if block_given?
    current_frame
  end
  
  def with_parent name_or_element, &block
    old_parent = @parent
    begin
      @parent    = name_or_element.kind_of?(Symbol) ? gui[name_or_element] : name_or_element
      block.call
    ensure
      @parent    = old_parent
    end
  end
  
  def top options = nil, &block
    options ||= {}
    frame_options = options.delete(:frame) || {}
    frame(nil, frame_options, &block).pack( {:side => :top, :fill => :x}.update(options) )
  end
  alias top_frame top
  
  def left options = nil, &block
    options ||= {}
    frame_options = options.delete(:frame) || {}
    frame(nil, frame_options, &block).pack( {:side => :left, :fill => :y}.update(options) )
  end
  alias left_frame left
  
  def root options = {:pady => 15, :padx => 15}, &block
    unless gui[:root]
      add(TkRoot, :root, options, &block)
      @parent = gui[:root]
    end
    gui[:root]
  end
  
  def enable *elements
    set_state 'normal', *elements
  end
  
  def disable *elements
    set_state 'disabled', *elements
  end
  
  def set_state state, *elements
    elements.each do |element_or_name|
      if element_or_name.kind_of?(Symbol) or element_or_name.kind_of?(String)
        element = gui[element_or_name]
      else
        element = element_or_name
      end
      element.state = state
    end
  end
  
  def bind_command name, key = nil, method_name = nil, &block
    block = method(method_name) unless block_given?
    gui[name].command = block
    root.bind(key,     &block) if key
  end
  
  def disable_elements_while *elements, &block
    waiting_text = elements.last.kind_of?(Hash) ? elements.pop : {}
    threads << Thread.new {
      previous_states, previous_texts = {}, {}
      elements.each do |element|
        puts "missing #{element}" if gui[element].nil?
        next if gui[element].nil?
        previous_states[element] = gui[element].state
        disable(element)
        if gui[element].respond_to?(:text)
          previous_texts[element] = gui[element].text
          gui[element].text = waiting_texts[element] || "Running..."
        end      
      end
      
      begin
        yield
      rescue
        say "#{$!}\n#{$!.backtrace.join("\n")}"
      ensure
        elements.each do |element|
          if gui[element].respond_to?(:text)
            gui[element].text = previous_texts[element]
          end      
          set_state(previous_states[element], element)
        end
      end
    }
    
  end
  
  
  
  def threads
    @threads ||= []
  end
  
  def gui
    @gui ||= HashWithIndifferentAccess.new
  end
  
  def add widget, name, options = {}, &block
    raise ArgumentError, "The name #{name.inspect} is already taken!" if name and gui.key?(name)
    parent = options.key?(:parent) ? 
              gui[options.delete(:parent)] :
              @parent || gui[:root]
    gui[name] = widget.new(parent) {
      {
        :takefocus => widget.ancestors.include?(TkEntry) || widget.ancestors.include?(TkButton),
        :highlightcolor => "#F6B256",
        
      }.update(options).each_pair { |property, value|
        value = [value] unless value.kind_of?(Array)
        send property, *value.compact
      }
      self.instance_eval(&block) if block_given?
    }
  end
  
  def say message
    Tk.messageBox :message => message
  end
  
  def start
    Tk.mainloop
  end
  
end

