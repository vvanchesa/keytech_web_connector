require 'sinatra/base'
require 'httparty'
require './KeytechElement'
require './EditorLayout'
require './EditorLayouts'
require './KeytechElementFile'
require './KeytechElementNote'
require './KeytechElementStatusHistoryEntry'
require './KeytechBomElement'
require './KeytechBomElements'

module Sinatra

  # This makes a sinatra extension, with access to session variable
  module KtApiHelper
    include HTTParty

    require_relative '../UserAccount'


    # Finds all elements by a search text
    def findElements(searchstring)
        
        user = UserAccount.get(session[:user])
        
        typeString=''
        # type=bla demo
        if (searchstring.start_with?('type='))
          # dann bis zum ersten leerzeichen suchen
          teststr = searchstring.partition('type=')[2]
          print "orgstr: " + searchstring
          print "test: " +teststr.strip
          typeString = teststr.strip
          searchstring = searchstring.partition(' ')[2] # Rechten Teil übergeben'
        end

        result = HTTParty.get(user.keytechAPIURL + "/searchitems", 
                                        :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword}, 
                                        :query => {:q => searchstring,:classtypes=>typeString})

        if result.code !=200 || result.code !=403
         # flash[:notice] = "#{result.code}: #{result.message}"
        end

        if result.code ==403
          # 403 = Unauthorized
          flash[:error] = "Unauthorized for API access. Please check keytech username and password in your account settings."
        end


        @itemarray=result["ElementList"]
    end

    
    # Loads the BOM of the given elementKey
    def loadElementBom(elementKey)
      user = currentUser
      #/elements/{ElementKey}/structure
      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}/bom", 
                                        :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

        keytechBomElements = loadElementBomData(result)
        print " Bom loaded "
        return keytechBomElements
    end
private 
  def loadElementBomData(result)
     
    bomItems = KeytechBomElements.new

     result["BomElementList"].each do |bomItem|
      newbomItem = KeytechBomElement.new

      # Unmwandeln des Arrays in eine Hash-Liste
      if bomItem["KeyValueList"]
          hash = {}
          bomItem["KeyValueList"].each do |pairs|
            hash[pairs['Key']] = pairs['Value']
          end
          newbomItem.keyValueList = hash
      end

      
      newbomItem.simpleElement = bomItem["SimpleElement"]
      
      bomItems.bomElements << newbomItem
    end
    return bomItems
  end


    # Loads excact one Element
    # responseAttributes one of LISTER|EDITOR|NONE|ALL  - defaults to NONE
    # If set additional attributes are added to result
    def loadElement(elementKey,responseAttributes = "")
      user = currentUser
      #/elements/{ElementKey}/structure
      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}?attributes=#{responseAttributes}", 
                                        :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

        keytechElement = loadElementData(result)
        return keytechElement
    end

private 
def loadElementData(result)
        keytechElement = KeytechElement.new
        element = result["ElementList"][0]

        keytechElement.createdAt =  element['CreatedAt']
        keytechElement.createdBy =  element['CreatedBy']
        keytechElement.createdByLong =  element['CreatedByLong']
        keytechElement.changedAt =  element['ChangedAt']
        keytechElement.changedBy =  element['ChangedBy']
        keytechElement.changedByLong =  element['changedByLong']
        keytechElement.elementDescription =  element['ElementDescription']
        keytechElement.elementDisplayName =  element['ElementDisplayName']
        keytechElement.elementKey =  element['ElementKey']
        keytechElement.elementName =  element['ElementName']
        keytechElement.elementStatus =  element['ElementStatus']
        keytechElement.elementTypeDisplayName =  element['ElementTypeDisplayName']
        keytechElement.elementVersion =  element['ElementVersion']
        keytechElement.hasVersions =  element['HasVersions']
        keytechElement.thumbnailHint =  element['ThumbnailHint']
        keytechElement.keyValueList = element['KeyValueList']

        return keytechElement
end

# Loads the underlying structure base an a given Element Key
    def loadElementStructure(elementKey)
      #user = UserAccount.get(session[:user])
      user = currentUser
      #/elements/{ElementKey}/structure
      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}/structure", 
                                        :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

        @itemarray=result["ElementList"]
    end

# Loads the thumbnail at the given key
  def loadElementThumbnail(thumbnailKey)



    # see: http://juretta.com/log/2006/08/13/ruby_net_http_and_open-uri/
    resource = "/elements/#{thumbnailKey}/thumbnail"
  #print "loaded: #{resource}"
    
    user = currentUser

    plainURI = user.keytechAPIURL.sub(/^https?\:\/\//, '').sub(/^www./,'')
    
    tnData = settings.cache.get(plainURI + resource)
    if !tnData
    # Thumbnail für 1 std cachen 
    #print "cache MISS "

      http = Net::HTTP.new(plainURI,443)
      http.use_ssl = true; 
      http.start do |http|
        req = Net::HTTP::Get.new(resource, {"User-Agent" =>
                              "keytech api downloader"})
        req.basic_auth(user.keytechUserName,user.keytechPassword)
        response = http.request(req)
    
        settings.cache.set(plainURI + resource,response.body)
        # return this!
        response.body  # Body contain image Data!
      end
    else
      #print "cache HIT! "
      return tnData
    end

  end

# Loads the editorlayout for this class
 def loadEditorLayout(elementKey)
      #user = UserAccount.get(session[:user])
      classKey =   elementKey.split(':')[0]

      user = currentUser
      #/elements/{ElementKey}/structure
      result = HTTParty.get(user.keytechAPIURL + "/classes/#{classKey}/editorlayout", 
                                              :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

      return layoutFromResult(result)
          
  end


  # Loads the bill of material layout
def loadBomLayout
    user = currentUser
    plainURI = user.keytechAPIURL.sub(/^https?\:\/\//, '').sub(/^www./,'')
   
    bomLayoutData = settings.cache.get(plainURI + "_BOM")
    if !bomLayoutData

      #/elements/{ElementKey}/structure
      result = HTTParty.get(user.keytechAPIURL + "/classes/bom/listerlayout", 
                                              :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

      bomLayoutData =  layoutFromResult(result)
      settings.cache.set(plainURI + "_BOM",bomLayoutData,60*60) #1 Stunde merken'
    end
    return bomLayoutData

  end

private
   def layoutFromResult(result)
        editorLayouts = EditorLayouts.new # [] # creates an array
          
          maxWidth = 0
          maxHeight = 0

          result["DesignerControls"].each do |layoutElement| # go through JSON response and make gracefully objects
      

          editorlayout = EditorLayout.new
          editorlayout.attributeAlignment = layoutElement['AttributeAlignment']
          editorlayout.attributeName = layoutElement['AttributeName']
          editorlayout.controlType = layoutElement['ControlType']
          editorlayout.dataDictionaryID = layoutElement['DataDictionaryID']
          editorlayout.dataDictionaryType = layoutElement['DataDictionaryType']
          editorlayout.displayName = layoutElement['Displayname']
          editorlayout.font = layoutElement['Font']
          editorlayout.name = layoutElement['Name']
          editorlayout.position = layoutElement['Position']
          editorlayout.sequence = layoutElement['Sequence']
          editorlayout.size = layoutElement['Size']
          
          height = editorlayout.size['height'] + editorlayout.position['y']
          (maxHeight< height)? maxHeight= height : maxHeight

          width = editorlayout.size['width'] + editorlayout.position['x']
          (maxWidth< width)? maxWidth= width : maxWidth

          editorLayouts.layouts << editorlayout

        end
        # maxinale grösse und breite  berechnen und dem Objekt zuweisen, für View wichtig
        editorLayouts.maxWidth =  maxWidth
        editorLayouts.maxHeight = maxHeight
        return editorLayouts
  end



# Loads the filelist of given element 
 def loadElementFileList(elementKey)

      user = currentUser

      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}/files", 
                                              :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

      files = [] # crates an empty array

      result["FileInfos"].each do |elementFile| # go through JSON response and make gracefully objects
      
            file = KeytechElementFile.new
            file.fileID = elementFile['FileID']
            file.fileName = elementFile['FileName']
            file.fileSize = elementFile['FileSize']
            file.fileSizeDisplay = elementFile['FileSizeDisplay']
            # normalized filename erstellen ? 
            files << file
          end
        return files
    end

 def loadElementNoteList(elementKey)

      user = currentUser

      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}/notes", 
                                              :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

      notes = [] # crates an empty array


      result["NotesList"].each do |note| # go through JSON response and make gracefully objects
      
            elementNote = KeytechElementNote.new
            elementNote.changedAt = note['ChangedAt']
            elementNote.changedBy = note['ChangedBy']
            elementNote.changedByLong = note['ChangedByLong']
            elementNote.createdAt = note['CreatedAt']
            elementNote.createdBy = note['CreatedBy']
            elementNote.createdByLong = note['CreatedByLong']
            elementNote.noteID = note['NoteID']
            elementNote.noteSubject = note['NoteSubject']
            elementNote.noteText = note['NoteText']            
            elementNote.noteType = note['NoteType']

            notes << elementNote
      end
      return notes
    end

# every status change is archived in a status history
# (a element with status "Finish" must have been "at work" at some time)
def loadElementStatusHistory(elementKey)

      user = currentUser

      result = HTTParty.get(user.keytechAPIURL + "/elements/#{elementKey}/statushistory", 
                                              :basic_auth => {
                                              :username => user.keytechUserName, 
                                              :password => user.keytechPassword})

      history = [] # crates an empty array


      result["StatusHistoryEntries"].each do |historyentry| # go through JSON response and make gracefully objects
      
            entry = KeytechElementStatusHistoryEntry.new
            entry.description = historyentry['Description']
            entry.signedByList = historyentry['SignedByList']
            entry.sourceStatus = historyentry['SourceStatus']
            entry.targetStatus = historyentry['TargetStatus']
            

            history << entry
      end
      return history  
    end



  end

  # Register this class
  helpers KtApiHelper

end
