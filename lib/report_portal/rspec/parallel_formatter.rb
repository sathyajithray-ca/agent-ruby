require 'securerandom'
require 'tree'
require 'rspec/core'
require 'pry'
require_relative '../../reportportal'
require_relative 'report'

module ReportPortal
  module RSpec
    class ParallelFormatter < Report

      FILE_WITH_LAUNCH_ID = Dir.pwd + "/parallel_launch_id_for_#{Process.ppid}.lck"
      FILE_WITH_PARALLEL_GROUPS_COUNT = Dir.pwd + "/parallel_groups_for_#{Process.ppid}.lck"

      @@parallel_count = ENV['PARALLEL_TEST_GROUPS'].to_i
      @@parallel_count_for_fininshing_launch = @@parallel_count

      ::RSpec::Core::Formatters.register self, :example_group_started, :example_group_finished,
                                         :example_started, :example_passed, :example_failed,
                                         :example_pending, :message

      
      def parallel?
        true
      end

      def initialize(_output)
        ENV['REPORT_PORTAL_USED'] = 'true'
      end

      def wait_for_launch
        p FILE_WITH_LAUNCH_ID
        until File.exist?(FILE_WITH_LAUNCH_ID) do
          p 'Sleeping'
          sleep 1
        end
      end

      def write_parallel_groups_count(count)
        File.open(FILE_WITH_PARALLEL_GROUPS_COUNT, 'w+') do |f|
          f.flock(File::LOCK_EX)
          f.write(count)
          f.flush
          f.flock(File::LOCK_UN)
        end
      end

      def read_parallel_groups_count
        File.open(FILE_WITH_PARALLEL_GROUPS_COUNT, 'r') do |f|
          f.flock(File::LOCK_SH)
          group_count = f.read
          f.flock(File::LOCK_UN)
          return group_count
        end
      end

      def start_launch
        @root_node = Tree::TreeNode.new(SecureRandom.hex)
        @current_group_node = @root_node
        p "Calling start_launch method"
        # if ParallelTests.first_process?
        if @@parallel_count.to_i == ENV['PARALLEL_TEST_GROUPS'].to_i && ParallelTests.first_process?
          description = ReportPortal::Settings.instance.description
          description = ARGV.map { |arg| arg.include?('rp_uuid=') ? 'rp_uuid=[FILTERED]' : arg }.join(' ')
          File.open(FILE_WITH_LAUNCH_ID, 'w+') do |f|
            f.flock(File::LOCK_EX)
            ReportPortal.start_launch(description)
            f.write(ReportPortal.launch_id)
            f.flush
            f.flock(File::LOCK_UN)
          end
          write_parallel_groups_count(ENV['PARALLEL_TEST_GROUPS'].to_i - 1)
          @@parallel_count = read_parallel_groups_count
          p 'Successfully launched'
          p " Launch created #{ReportPortal.launch_id}"
        else
          wait_for_launch
          File.open(FILE_WITH_LAUNCH_ID, 'r') do |f|
            f.flock(File::LOCK_SH)
            ReportPortal.launch_id = f.read
            f.flock(File::LOCK_UN)
          end
        end
      end
      
      def example_group_started(group_notification)
        start_launch
        description = group_notification.group.description
        if description.size < MIN_DESCRIPTION_LENGTH
          p "Group description should be at least #{MIN_DESCRIPTION_LENGTH} characters ('group_notification': #{group_notification.inspect})"
          return
        end
        item = ReportPortal::TestItem.new(name: description[0..MAX_DESCRIPTION_LENGTH - 1],
                                          type: :TEST,
                                          id: nil,
                                          start_time: ReportPortal.now,
                                          description: '',
                                          closed: false,
                                          tags: [])
        group_node = Tree::TreeNode.new(SecureRandom.hex, item)
        if group_node.nil?
          p "Group node is nil for item #{item.inspect}"
        else
          @current_group_node << group_node unless @current_group_node.nil? # make @current_group_node parent of group_node
          @current_group_node = group_node
          group_node.content.id = ReportPortal.start_item(group_node)
        end
      end

      def example_group_finished(_group_notification)
        if !@current_group_node.nil?
          ReportPortal.finish_item(@current_group_node.content)
          # @current_group_node = @current_group_node.parent
        end
        @@parallel_count_for_fininshing_launch = read_parallel_groups_count
        if @@parallel_count_for_fininshing_launch.to_i == 0
          $stdout.puts "Finishing launch #{ReportPortal.launch_id}"
          p "Finishing launch #{ReportPortal.launch_id}"
          ReportPortal.finish_launch(ReportPortal.now)
        end

        # p "Process First Process? #{ParallelTests.first_process?}"
        # if ParallelTests.first_process?
        #   p 'Skipping as it is first process'
        #   return
        # end
        # if @@parallel_count_for_fininshing_launch.to_i == ENV['PARALLEL_TEST_GROUPS'].to_i && ParallelTests.first_process?
        #   @@parallel_count_for_fininshing_launch = read_parallel_groups_count
        #   ParallelTests.wait_for_other_processes_to_finish
        #   # File.delete(FILE_WITH_LAUNCH_ID)
        #   # unless attach_to_launch?
        #   $stdout.puts "Finishing launch #{ReportPortal.launch_id}"
        #   p "Finishing launch #{ReportPortal.launch_id}"
        #   # ReportPortal.close_child_items(nil)
        #   ReportPortal.finish_launch(ReportPortal.now)
        #   # end
        # end
      end

      def attach_to_launch?
        ReportPortal::Settings.instance.formatter_modes.include?('attach_to_launch')
      end
    end
  end
end
