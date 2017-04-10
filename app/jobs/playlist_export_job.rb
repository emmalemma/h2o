require 'tempfile'
require 'uri'

# TODO: Now that it's stable, this would benefit from refactoring into the
#   intended ExportService class.
class PlaylistExportJob < ApplicationJob

  class ExportException < StandardError; end

  def perform(opts)
    request_url = opts[:request_url]
    params = opts[:params]
    email_address = opts[:email_to]

    #required for owners to export their own private content
    params.merge!(:_h2o_session => opts[:session_cookie])
    export_format = params[:export_format]

    exported_file = nil
    begin
      if export_format == 'doc'
        exported_file = export_as_doc(request_url, params)
      elsif export_format == 'pdf'
        exported_file = export_as_pdf(request_url, params)
      else
        raise "Unsupported export_format '#{export_format}'"
      end
    rescue => e
      Rails.logger.warn "~~export_as exception: #{e}"
      #ExceptionNotifier.notify_exception(e)
      raise e
    end

    export_result = ExportService::ExportResult.new(
    content_path: exported_file,
    item_name: params['item_name'],
    format: params['export_format'],
    )

    if email_address
      email_download_link(export_result.content_path, email_address)
    end

    export_result
  end

  def email_download_link(content_path, email_address)  #_base
    Notifier.export_download_link(content_path, email_address).deliver
  end

  def export_as_doc(request_url, params)  #_doc
    convert_to_mime_file(fetch_playlist_html(request_url, params))
  end

  def output_file_path(params)  #_base
    base_dir = Rails.root.join('public/exports')
    FileUtils.mkdir(base_dir) unless File.exist?(base_dir)

    out_dir = Dir::Tmpname.create(params[:id], base_dir) {|path| path}
    FileUtils.mkdir(out_dir) unless File.exist?(out_dir)

    filename = (params[:item_name].to_s || "download").parameterize.underscore
    out_dir + '/' + filename + '.' + params[:export_format]
  end

  def create_phantomjs_options_file(directory, params)
    ExportService::Cookies.phantomjs_options_file(directory, params)
  end

  def fetch_playlist_html(request_url, params)  #_doc
    target_url = get_target_url(request_url)
    out_file = output_file_path(params)
    out_file.sub!(/#{File.extname(out_file)}$/, '.html')

    options_tempfile = create_phantomjs_options_file(
      File.dirname(out_file),
      params
      )

    command = [
               'phantomjs',
               # '--debug=true',
               'app/assets/javascripts/phantomjs-export.js',
               target_url,
               out_file,
               options_tempfile,
              ]
    Rails.logger.warn command.join(' ')

    exit_code = nil
    command_output = []
    Open3.popen2e(*command) do |_, out_err, wait_thread|
      out_err.each {|line|
        Rails.logger.warn "PHANTOMJS: #{line.rstrip}"
        command_output << line
      }
      exit_code = wait_thread.value.exitstatus
    end
    command_text = command_output.join("\n")

    if exit_code == 0
      out_file.tap {|x| Rails.logger.warn "Created #{x}" }
    else
      Rails.logger.warn "Export failed for command: #{command.join(' ')}\nOutput: #{command_text}"
      raise ExportException, command_text
    end
  end

  def convert_to_mime_file(input_file)  #_doc
    boundary = "----=_NextPart_ZROIIZO.ZCZYUACXV.ZARTUI"
    lines = []
    lines << "MIME-Version: 1.0"
    lines << "Content-Type: multipart/related; boundary=\"#{boundary}\""
    lines << ""
    lines << '--' + boundary
    lines << "Content-Location: file:///C:/boop.htm"
    lines << "Content-Transfer-Encoding: base64"
    lines << "Content-Type: text/html; charset=\"UTF-8\""
    lines << ""
    lines << Base64.encode64(File.read(input_file))

    output_file = input_file.sub(/#{File.extname(input_file)}$/, '.doc')

    #Note: only the last boundary seems to need the final trailing "--". That
    # could just be Word being, well, Word.
    delim = "\n"
    File.write(output_file, lines.join(delim) + delim + "--" + boundary + "--")
    output_file
  end

  def html_head_open?(line)  #_pdf
    line.match(/<head\b/i)
  end

  def html_body_close?(line)  #_pdf
    line.match(/<\/body>/i)
  end

  def export_as_pdf(request_url, params)  #_pdf
    command = pdf_command(request_url, params)
    output_file = command.last
    Rails.logger.warn command.join(' ')

    exit_code = nil
    command_output = []
    html_file = command.last.sub(/\.pdf$/, '.html')
    html_has_started = false
    html_has_finished = false

    File.open(html_file, 'w') do |log|
      # In addition to running the exporter, this captures the rendered HTML
      # the exporter is seeing, the same way we get it for free with phantomjs.
      Open3.popen2e(*command) do |_, out_err, wait_thread|
        out_err.each do |line|
          html_has_started = true if html_head_open?(line)
          html_has_finished = true if html_body_close?(line)

          if html_has_started && (!html_has_finished || html_body_close?(line))
            log.write(line)
          else
            Rails.logger.warn "WKHTMLTOPDF: #{line.rstrip}"
            command_output << line
          end
        end

        exit_code = wait_thread.value.exitstatus
      end
    end
    command_text = command_output.join

    if exit_code == 0
      output_file
    else
      Rails.logger.warn "Export failed for command: #{command.join(' ')}\nOutput: #{command_text}"
      raise ExportException, command_text
    end
  end

  def convert_h_tags(doc)
    # Convert H tags to divs to let us control the H tags in a document, which
    #   controls the H tags that are used on the table of contents, both in
    #   Word export and in the JavaScript TOC code.
    # Accepts a string or Nokogiri document
    if !doc.respond_to?(:xpath)
      doc.gsub!(/\r\n/, '')
      #NOTE: This situation needs to be handled better because this method
      #changes $doc by reference if it's already a Nokogiri doc, despite
      #how it also returns the resulting doc
      return '' if doc.in?(['', '<br>'])
      doc = Nokogiri::HTML.parse(doc)
    end

    doc.xpath("//h1 | //h2 | //h3 | //h4 | //h5 | //h6").each do |node|
      # NOTE: The nxp class is used to exclude this div from xpaths counts (e.g. /div[3])
      #   because we are changing the number of divs in a document
      h_level = node.name.match(/h(\d)/)[1]
      node['class'] = node['class'].to_s + " new-h#{h_level} nxp"
      node.name = 'div'
    end

    doc
  end

  def inject_doc_styles(doc)  #_both
    # NOTE: Using doc.css("center").wrap(...) here broke annotations, probably because
    #   it added another layer to the local DOM, which meant xpath_start and/or xpath_end
    #   values in the relevant annotation didn't match up with the DOM any more.
    doc.css("center").add_class("Case-header")
    doc.css("p").add_class("Item-text")

    cih_selector = '//div[not(ancestor::center) and contains(concat(" ", normalize-space(@class), " "), "new-h2")]'
    doc.xpath(cih_selector).each do |el|
      # Word style classes only work when they are the first class for a given element.
      el['class'] = "Case-internal-header " + el['class'].to_s
    end
  end

  def pdf_page_options(params)  #_pdf
    [
      '--no-stop-slow-scripts',
      '--debug-javascript',
      '--javascript-delay 1000',
      '--window-status annotation_load_complete',
      '--print-media-type',  # NOTE: DOC export ignores this.
      pdf_javascript_deadman_switch('annotation_load_complete'),
    ]
  end

  def pdf_javascript_deadman_switch(status)  #_pdf
    # This works with the --window-status switch to prevent wkhtmltopdf from
    # hanging forever if something goes wrong in the page. Note that this won't make
    # it through our system call correctly if there are spaces inside the JS. Seriously.
    "--run-script if(window.status!='loading_h2o'&&window.status!='#{status}'){window.status='#{status}'};"
  end

  def pdf_command(request_url, params)  #_pdf
    #request_url is the full request URI that is posting TO this page. We need
    # pieces of that that to construct the URL we are going to pass to wkhtmltopdf
    global_options = %w[margin-top margin-right margin-bottom margin-left].map {|name|
      "--#{name} #{params[name]}"
    }.join(' ')

    output_file_path = output_file_path(params)
    toc_params = params.merge('base_dir' => File.dirname(output_file_path))
    toc_options = ExportService::TableOfContents::PDF.generate(request_url, toc_params)

    target_url = get_target_url(request_url)
    page_options = pdf_page_options(params)
    cookie_string = ExportService::Cookies.forwarded_pdf_cookies(params)

    prep_output_file_path(output_file_path)

    [
      'wkhtmltopdf',
      global_options,
      toc_options,
      'page',
      target_url,
      page_options,
      cookie_string,
      output_file_path,  #This always has to be last in this array
    ].flatten.join(' ').split
  end

  def prep_output_file_path(output_file_path)  #_pdf or _base if useful there
    FileUtils.mkdir_p(File.dirname(output_file_path))
  end

  def get_target_url(request_url)  #_base
    page_name = request_url.match(/\/playlists\//) ? 'export_all' : 'export'
    request_url.sub(/export_as$/, page_name)
  end
end
