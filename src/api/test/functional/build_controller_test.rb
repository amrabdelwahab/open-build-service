require File.dirname(__FILE__) + '/../test_helper'

require 'rexml/document'
include REXML

class BuildControllerTest < ActionController::IntegrationTest 

  fixtures :all

  def setup
    prepare_request_valid_user
  end

  def test_index
    get "/build"
    assert_response :success
    assert_match(/entry name="home:Iggy"/, @response.body)
    get "/build/home:Iggy"
    assert_response :success
    assert_match(/entry name="10.2"/, @response.body)
    get "/build/home:Iggy/10.2"
    assert_response :success
    assert_match(/entry name="i586"/, @response.body)
    get "/build/home:Iggy/10.2/i586"
    assert_response :success
    assert_match(/entry name="TestPack"/, @response.body)
    get "/build/home:Iggy/10.2/i586/TestPack"
    assert_response :success
    assert_match(/binary filename="package-1.0-1.i586.rpm"/, @response.body)

    # FIXME: hope this is not 400 because its another hidden OBS interconnect case
    get "/build/blabla"
    assert_response 404
    get "/build/home:Iggy/blabla"
    assert_response 404
    get "/build/home:Iggy/10.2/blabla"
    assert_response 404
  end

  def test_upload_binaries
    ActionController::IntegrationTest::reset_auth
    post "/build/home:Iggy/10.2/i586/TestPack", nil
    assert_response 401

    prepare_request_with_user "adrian", "so_alone"
    post "/build/home:Iggy/10.2/i586/TestPack", nil
    assert_response 403

    prepare_request_with_user "king", "sunflower"
    post "/build/home:Iggy/10.2/i586/TestPack", nil
    assert_response 400 # actually a success, it reached the backend
    assert_tag :tag => "status", :attributes => { :code => "400", :origin => "backend" }

    # check not supported methods
    post "/build/home:Iggy/10.2/i586/_repository", nil
    assert_response 404
    assert_tag :tag => "status", :attributes => { :code => "unknown_package" }
    put "/build/home:Iggy/10.2/i586/TestPack", nil
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "invalid_http_method" }
    delete "/build/home:Iggy/10.2/i586/TestPack"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "invalid_http_method" }
  end

  def test_delete_from_repository
    ActionController::IntegrationTest::reset_auth
    delete "/build/home:Iggy/10.2/i586/_repository/delete_me.rpm"
    assert_response 401

    prepare_request_with_user "adrian", "so_alone"
    delete "/build/home:Iggy/10.2/i586/_repository/delete_me.rpm"
    assert_response 403
    delete "/build/home:Iggy/10.2/i586/_repository/not_existing.rpm"
    assert_response 403
    get "/build/home:Iggy/10.2/i586/_repository/delete_me.rpm"
    assert_response :success

    prepare_request_with_user "Iggy", "asdfasdf"
    delete "/build/home:Iggy/10.2/i586/_repository/delete_me.rpm"
    assert_response :success
    delete "/build/home:Iggy/10.2/i586/_repository/not_existing.rpm"
    assert_response 404
    get "/build/home:Iggy/10.2/i586/_repository/delete_me.rpm"
    assert_response 404

    delete "/build/home:Iggy/10.2/i586/TestPack/package-1.0-1.i586.rpm"
    assert_response 400
    assert_match(/invalid_operation/, @response.body)
    assert_match(/Delete operation of build results is not allowed/, @response.body)
  end

  def test_read_access_hidden_project_index
    # ACL(project_index)
    # testing build_controller project_index 
    # currently this test shows that there's an information leak.
    get "/build"
    assert_response :success
    assert_no_match(/entry name="HiddenProject"/, @response.body)
    # retry with maintainer
    prepare_request_with_user "adrian", "so_alone"
    get "/build"
    assert_response :success
    assert_match(/entry name="HiddenProject"/, @response.body)
    prepare_request_valid_user
  end

  def test_buildinfo
    # just testing routing
    get "/build/buildinfo"
    assert_response 404
    assert_match(/project 'buildinfo' does not exist/, @response.body)

    # get source info to compare with
    get "/source/home:Iggy/TestPack"
    assert_response :success
    assert_no_tag :tag => "xsrcmd5" # is no link, srcmd5 is valid
    node = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = node.srcmd5
    # this is only testing the rep server buildinfo, not the one generated by scheduler
    get "/build/home:Iggy/10.2/i586/TestPack/_buildinfo"
    assert_response :success
    rev="2"
    b_cnt="2"
    ci_cnt="42"
    assert_tag :tag => "buildinfo"
    assert_tag :tag => "arch", :content => "i586"
    assert_tag :tag => "srcmd5", :content => srcmd5
    assert_tag :tag => "file", :content => "TestPack.spec"
    assert_tag :tag => "debuginfo", :content => "0"
    assert_tag :tag => "release", :content => "#{ci_cnt}.#{b_cnt}"
    assert_tag :tag => "versrel", :content => "1.0-#{ci_cnt}"
    assert_tag :tag => "rev", :content => rev
    assert_tag :tag => "path", :attributes => { :project => "home:Iggy", :repository => "10.2" }
    buildinfo = ActiveXML::XMLNode.new(@response.body)

    # find scheduler job and compare it with buildinfo
    jobfile=File.new("#{RAILS_ROOT}/tmp/backend_data/jobs/i586/home:Iggy::10.2::TestPack-#{srcmd5}")
    schedulerjob = Document.new(jobfile).root
# FIXME: to be implemented, compare scheduler job with rep server job
#    schedulerjob.elements.each do |jobnode|
#      puts "test", jobnode.inspect
#    end
    
  end

  # FIXME: test buildinfo for hidden packages, too.

  def test_package_index
    get "/build/home:Iggy/10.2/i586/TestPack"
    assert_response :success
    assert_tag( :tag => "binarylist" ) 
  end

  def test_read_access_hidden_package_index
    get "/build/HiddenProject/nada/i586/pack"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/nada/i586/pack"
    assert_response :success
    assert_tag( :tag => "binarylist" ) 
    prepare_request_valid_user
  end

  def test_logfile
    get "/build/home:Iggy/10.2/i586/TestPack/_log"
    assert_response :success
    get "/build/home:Iggy/10.2/i586/notthere/_log"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
  end

  #FIXME2.1: add test case for buildlog of source access protected content (needs to be 403)

  def test_read_access_hidden_logfile
    get "/build/HiddenProject/nada/i586/pack/_log"
    assert_response 404
    assert_match(/Unknown project 'HiddenProject/, @response.body)
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/nada/i586/pack/_log"
    assert_response :success
    prepare_request_valid_user
  end

  def test_read_access_binarydownload_logfile
    # build_controller.rb:    # ACL(logfile): binarydownload denies logfile acces
    get "/build/BinaryprotectedProject/nada/i586/bdpack/_log"
    assert_response 403
    assert_match(/download_binary_no_permission/, @response.body)
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "binary_homer", "homer"
    get "/build/BinaryprotectedProject/nada/i586/bdpack/_log"
    assert_response :success
    prepare_request_valid_user
  end

  def test_result
    get "/build/home:Iggy/_result"
    assert_response :success
    assert_tag :tag => "resultlist", :children =>  { :count => 2 }
  end

  def test_read_access_hidden_result_prj
    get "/build/HiddenProject/_result"
    assert_response 404
    # retry with maintainer
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/_result"
    assert_response :success
    assert_tag :tag => "resultlist"
    prepare_request_valid_user
  end

  def test_read_access_privacy_result_prj
    get "/build/ViewprotectedProject/_result"
    assert_response :success
    assert_no_tag :tag => "resultlist"
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "view_homer", "homer"
    get "/build/ViewprotectedProject/_result"
    assert_response :success
    assert_tag :tag => "resultlist"
    # retry with reader
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian_reader", "so_alone"
    get "/build/ViewprotectedProject/_result"
    assert_response :success
    assert_tag :tag => "resultlist"
    prepare_request_valid_user
  end

  def test_read_access_hidden_result_pkg
    get "/build/HiddenProject/_result?package=pack"
    assert_response 404
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/_result?package=pack"
    assert_response :success
    assert_tag :tag => "resultlist"
    prepare_request_valid_user

  end

  def test_read_access_privacy_result_pkg
    get "/build/ViewprotectedProject/_result?package=pack"
    assert_response :success
    assert_no_tag :tag => "resultlist"
    # retry with maintainer
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "view_homer", "homer"
    get "/build/ViewprotectedProject/_result?package=pack"
    assert_response :success
    assert_tag :tag => "resultlist"
    # retry with reader
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian_reader", "so_alone"
    get "/build/ViewprotectedProject/_result?package=pack"
    assert_response :success
    assert_tag :tag => "resultlist"
    prepare_request_valid_user
  end

  def test_binary_view
    get "/build/home:Iggy/10.2/i586/TestPack/file?view=fileinfo"
    assert_response 404
    assert_match(/file: No such file or directory/, @response.body)

    get "/build/home:Iggy/10.2/i586/TestPack/package-1.0-1.i586.rpm?view=fileinfo"
    assert_response :success
    #FIXME validate xml content
  end
  
  def test_read_access_hidden_binary_view
    # 404 on invalid
    get "/build/HiddenProject/nada/i586/pack/package?view=fileinfo"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    get "/build/HiddenProject/nada/i586/pack/package-1.0-1.i586.rpm?view=fileinfo"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    # success on valid
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/nada/i586/pack/package?view=fileinfo"
    assert_response 404
    assert_match(/No such file or directory/, @response.body)
    get "/build/HiddenProject/nada/i586/pack/package-1.0-1.i586.rpm?view=fileinfo"
    assert_response :success
    prepare_request_valid_user
  end

  def test_read_access_binarydownload_binary_view
    # 404 on invalid
    get "/build/BinaryprotectedProject/nada/i586/bdpack/package?view=fileinfo"
    assert_response 403
    assert_match(/download_binary_no_permission/, @response.body)
    get "/build/BinaryprotectedProject/nada/i586/bdpack/package-1.0-1.i586.rpm?view=fileinfo"
    assert_response 403
    assert_match(/download_binary_no_permission/, @response.body)
    # success on valid
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "binary_homer", "homer"
    get "/build/BinaryprotectedProject/nada/i586/bdpack/package?view=fileinfo"
    assert_response 404
    assert_match(/No such file or directory/, @response.body)
    get "/build/BinaryprotectedProject/nada/i586/bdpack/package-1.0-1.i586.rpm?view=fileinfo"
    assert_response :success
    prepare_request_valid_user
  end

  def test_file
    get "/build/home:Iggy/10.2/i586/TestPack"
    assert_response 200
    get "/build/home:Iggy/10.2/i586/TestPack/package-1.0-1.i586.rpm"
    assert_response 200
    get "/build/home:Iggy/10.2/i586/TestPack/NOT_EXISTING"
    assert_response 404
    assert_match(/NOT_EXISTING: No such file or directory/, @response.body)
  end

  def test_read_access_hidden_file
    get "/build/HiddenProject/nada/i586/pack/"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    get "/build/HiddenProject/nada/i586/pack/package-1.0-1.i586.rpm"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    get "/build/HiddenProject/nada/i586/pack/NOT_EXISTING"
    assert_response 404
    assert_match(/Unknown package/, @response.body)
    # success on valid
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone"
    get "/build/HiddenProject/nada/i586/pack/"
    assert_response :success
    assert_match(/binarylist/, @response.body)
    get "/build/HiddenProject/nada/i586/pack/package-1.0-1.i586.rpm"
    assert_response :success
    get "/build/HiddenProject/nada/i586/pack/NOT_EXISTING"
    assert_match(/NOT_EXISTING: No such file or directory/, @response.body)
    prepare_request_valid_user
  end

  def test_project_index
    get "/build/home:Iggy"
    assert_response :success
    assert_tag :tag => "directory", :children =>  { :count => 1 }

    put "/build/home:Iggy", :cmd => 'say_hallo'
    assert_response 403
    assert_match(/No permission to execute command on project/, @response.body)

    post "/build/home:Iggy", :cmd => 'say_hallo'
    assert_response 400
    assert_match(/unsupported POST command/, @response.body)

    prepare_request_with_user "Iggy", "asdfasdf" 
    post "/build/home:Iggy"
    assert_response 400
    post "/build/home:Iggy?cmd=say_hallo"
    assert_response 400
    post "/build/home:NotExisting?cmd=wipe"
    assert_response 404
    assert_match(/Project does not exist/, @response.body)
    post "/build/home:Iggy?cmd=wipe&package=DoesNotExist"
    assert_response 404
    assert_match(/unknown package: DoesNotExist/, @response.body)
  
    post "/build/home:Iggy?cmd=wipe"
    assert_response :success
    post "/build/home:Iggy?cmd=wipe&package=TestPack"
    assert_response :success

    post "/build/home:Iggy?cmd=abortbuild"
    assert_response :success
    post "/build/home:Iggy?cmd=abortbuild&package=TestPack"
    assert_response :success

    prepare_request_with_user "adrian", "so_alone" 
    post "/build/home:Iggy?cmd=wipe"
    assert_response 403
    assert_match(/No permission to execute command on project/, @response.body)
    post "/build/home:Iggy?cmd=wipe&package=TestPack"
    assert_response 403
    assert_match(/No permission to execute command on package/, @response.body)

  end

  def test_read_access_hidden_project_index
    #invalid
    get "/build/HiddenProject"
    assert_response 404
    assert_match(/Unknown project/, @response.body)

    put "/build/HiddenProject", :cmd => 'say_hallo'
    assert_response 404
    assert_match(/Unknown project/, @response.body)

    post "/build/HiddenProject", :cmd => 'say_hallo'
    assert_response 404
    assert_match(/Unknown project/, @response.body)

    post "/build/HiddenProject?cmd=wipe"
    assert_response 404
    assert_match(/Unknown project/, @response.body)

    post "/build/HiddenProject?cmd=wipe&package=TestPack"
    assert_response 404
    assert_match(/Unknown project/, @response.body)

    #valid
    ActionController::IntegrationTest::reset_auth
    prepare_request_with_user "adrian", "so_alone" 
    get "/build/HiddenProject"
    assert_response :success
    assert_tag :tag => "directory", :children =>  { :count => 1 }

    put "/build/HiddenProject", :cmd => 'say_hallo'
    assert_response 403
    assert_match(/No permission to execute command on project/, @response.body)

    post "/build/HiddenProject", :cmd => 'say_hallo'
    assert_response 400
    assert_match(/illegal_request/, @response.body)

    post "/build/HiddenProject?cmd=wipe&package=DoesNotExist"
    assert_response 404
    assert_match(/unknown package: DoesNotExist/, @response.body)

    post "/build/HiddenProject?cmd=wipe"
    assert_response :success
    post "/build/HiddenProject?cmd=wipe&package=pack"
    assert_response :success
  end

  def test_remoteinstance
    # check that we handle this correctly - the remoteinstance is only in the database
    get "/build/RemoteInstance:BaseDistro/_result?view=summary"
    assert_response 404
  end
 
  # FIXME: remoteinstance and ACL ?!
end
