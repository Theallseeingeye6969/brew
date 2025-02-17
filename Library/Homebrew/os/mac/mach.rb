# typed: true
# frozen_string_literal: true

require "macho"

# {Pathname} extension for dealing with Mach-O files.
#
# @api private
module MachOShim
  extend Forwardable

  delegate [:dylib_id] => :macho

  def macho
    @macho ||= MachO.open(to_s)
  end
  private :macho

  def mach_data
    @mach_data ||= begin
      machos = []
      mach_data = []

      if MachO::Utils.fat_magic?(macho.magic)
        machos = macho.machos
      else
        machos << macho
      end

      machos.each do |m|
        arch = case m.cputype
        when :x86_64, :i386, :ppc64, :arm64, :arm then m.cputype
        when :ppc then :ppc7400
        else :dunno
        end

        type = case m.filetype
        when :dylib, :bundle then m.filetype
        when :execute then :executable
        else :dunno
        end

        mach_data << { arch: arch, type: type }
      end

      mach_data
    rescue MachO::NotAMachOError
      # Silently ignore errors that indicate the file is not a Mach-O binary ...
      []
    rescue
      # ... but complain about other (parse) errors for further investigation.
      onoe "Failed to read Mach-O binary: #{self}"
      raise if Homebrew::EnvConfig.developer?

      []
    end
  end
  private :mach_data

  # TODO: See if the `#write!` call can be delayed until
  # we know we're not making any changes to the rpaths.
  def delete_rpath(rpath, **options)
    macho.delete_rpath(rpath, options)
    macho.write!
  end

  def change_rpath(old, new, **options)
    macho.change_rpath(old, new, options)
    macho.write!
  end

  def change_dylib_id(id, **options)
    macho.change_dylib_id(id, options)
    macho.write!
  end

  def change_install_name(old, new, **options)
    macho.change_install_name(old, new, options)
    macho.write!
  end

  def dynamically_linked_libraries(except: :none, resolve_variable_references: true)
    lcs = macho.dylib_load_commands.reject { |lc| lc.type == except }

    names = lcs.map(&:name).map(&:to_s).uniq

    names.map! { |name| resolve_variable_name(name) } if resolve_variable_references

    names
  end

  def rpaths(resolve_variable_references: true)
    names = macho.rpaths.uniq

    names.map! { |name| resolve_variable_name(name) } if resolve_variable_references

    names
  end

  def resolve_variable_name(name)
    if name.start_with? "@loader_path"
      Pathname(name.sub("@loader_path", dirname)).cleanpath.to_s
    elsif name.start_with?("@executable_path") && binary_executable?
      Pathname(name.sub("@executable_path", dirname)).cleanpath.to_s
    else
      name
    end
  end

  def archs
    mach_data.map { |m| m.fetch :arch }
  end

  def arch
    case archs.length
    when 0 then :dunno
    when 1 then archs.first
    else :universal
    end
  end

  def universal?
    arch == :universal
  end

  def i386?
    arch == :i386
  end

  def x86_64?
    arch == :x86_64
  end

  def ppc7400?
    arch == :ppc7400
  end

  def ppc64?
    arch == :ppc64
  end

  def dylib?
    mach_data.any? { |m| m.fetch(:type) == :dylib }
  end

  def mach_o_executable?
    mach_data.any? { |m| m.fetch(:type) == :executable }
  end

  alias binary_executable? mach_o_executable?

  def mach_o_bundle?
    mach_data.any? { |m| m.fetch(:type) == :bundle }
  end
end
