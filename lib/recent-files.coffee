#--- localStorage DB
DB = (key) ->
  @key = key
  return @
DB.prototype.getData = ->
  data = localStorage[@key]
  data = if data? then JSON.parse(data) else {}
  return data
DB.prototype.setData = (data) ->
  localStorage[@key] = JSON.stringify(data)
DB.prototype.get = (name) ->
  data = @getData()
  return data[name]
DB.prototype.set = (name, value) ->
  data = @getData()
  data[name] = value
  @setData(data)


#--- RecentFiles
RecentFiles = ->
  @db = new DB('recentPaths')
  return @

#--- RecentFiles: Event Handlers
RecentFiles.prototype.onLocalStorageEvent = (e) ->
  if e.key is @db.key
    @update()

RecentFiles.prototype.onUriOpened = ->
  editor = atom.workspace.getActiveEditor()
  filePath = editor?.buffer?.file?.path

  # Ignore anything thats not a file.
  return unless filePath
  return unless filePath.indexOf '://' is -1

  @insertFilePath(filePath) if filePath

#--- RecentFiles: Listeners
RecentFiles.prototype.addCommandListeners = ->
  #--- Commands
  # recent-files:open-recent-file-#
  for index, path of @db.get('files')
    do (path) => # Explicit closure
      atom.workspaceView.on "recent-files:open-recent-file-#{index}", =>
        @openFile path

  # recent-files:open-recent-path-#
  for index, path of @db.get('paths')
    do (path) => # Explicit closure
      atom.workspaceView.on "recent-files:open-recent-path-#{index}", =>
        @openPath path

  # recent-files:clear
  atom.workspaceView.on "recent-files:clear", =>
    @db.set('files', [])
    @db.set('paths', [])
    @update()


RecentFiles.prototype.openFile = (path) ->
  atom.workspace.open path

RecentFiles.prototype.openPath = (path) ->
  atom.open { pathsToOpen: [path] }

RecentFiles.prototype.addListeners = ->
  #--- Commands
  @addCommandListeners()

  #--- Events
  atom.workspace.on 'uri-opened', @onUriOpened.bind(@)

  # Notify other windows during a setting data in localStorage.
  window.addEventListener "storage", @onLocalStorageEvent.bind(@)

RecentFiles.prototype.removeCommandListeners = ->
  #--- Commands
  for index, path of @db.get('files')
    atom.workspaceView.off "recent-files:open-recent-file-#{index}"
  for index, path of @db.get('paths')
    atom.workspaceView.off "recent-files:open-recent-path-#{index}"
  atom.workspaceView.off "recent-files:clear"

RecentFiles.prototype.removeListeners = ->
  #--- Commands
  @removeCommandListeners()

  #--- Events
  atom.workspaceView.off 'editor:attached'
  window.removeEventListener 'storage', @storageHandler.bind(@)

#--- RecentFiles: Methods
RecentFiles.prototype.init = ->
  @addListeners()

  # Migrate v0.3.0 -> v1.0.0
  if @db.getData() instanceof Array
    @db.setData({ paths: @db.getData() })

  # Defaults
  @db.set('paths', []) unless @db.get('paths')
  @db.set('files', []) unless @db.get('files')

  @insertCurrentPath()
  @update()

RecentFiles.prototype.insertCurrentPath = ->
  return unless atom.project.getRootDirectory()

  path = atom.project.getRootDirectory().path
  recentPaths = @db.get('paths')

  # Remove if already listed
  index = recentPaths.indexOf path
  if index != -1
    recentPaths.splice index, 1

  recentPaths.splice 0, 0, path

  # Limit
  maxRecentDirectories = atom.config.get('recent-files.maxRecentDirectories')
  if recentPaths.length > maxRecentDirectories
    recentPaths.splice maxRecentDirectories, recentPaths.length - maxRecentDirectories

  @db.set('paths', recentPaths)
  @update()

 RecentFiles.prototype.insertFilePath = (path) ->
  recentFiles = @db.get('files')

  # Remove if already listed
  index = recentFiles.indexOf path
  if index != -1
    recentFiles.splice index, 1

  recentFiles.splice 0, 0, path

  # Limit
  maxRecentFiles = atom.config.get('recent-files.maxRecentFiles')
  if recentFiles.length > maxRecentFiles
    recentFiles.splice maxRecentFiles, recentFiles.length - maxRecentFiles

  @db.set('files', recentFiles)
  @update()

#--- RecentFiles: Menu
RecentFiles.prototype.createSubmenu = ->
  submenu = []
  submenu.push { command: "pane:reopen-closed-item", label: "Reopen Closed File" }
  submenu.push { type: "separator" }

  # Files
  recentFiles = @db.get('files')
  if recentFiles.length
    for index, path of recentFiles
      submenu.push { label: path, command: "recent-files:open-recent-file-#{index}" }
    submenu.push { type: "separator" }

  # Root Paths
  recentPaths = @db.get('paths')
  if recentPaths.length
    for index, path of recentPaths
      submenu.push { label: path, command: "recent-files:open-recent-path-#{index}" }
    submenu.push { type: "separator" }

  submenu.push { command: "recent-files:clear", label: "Clear List" }
  return submenu

RecentFiles.prototype.updateMenu = ->
  # need to place our menu in top section
  for dropdown in atom.menu.template
    if dropdown.label is "&File"
      for item in dropdown.submenu
        if item.command is "pane:reopen-closed-item" or item.label is "Open Recent"
          delete item.command
          item.label = "Open Recent"
          item.submenu = @createSubmenu()
          atom.menu.update()
          break # break for item
      break # break for dropdown

#--- RecentFiles:
RecentFiles.prototype.update = ->
  @removeCommandListeners()
  @updateMenu()
  @addCommandListeners()

RecentFiles.prototype.destroy = ->
  @removeListeners()


#--- Module
module.exports =
  configDefaults:
    maxRecentFiles: 8
    maxRecentDirectories: 8

  model: null

  activate: ->
    atom.config.setDefaults('recent-files', @configDefaults)
    @model = new RecentFiles()
    @model.init()

  deactivate: ->
    @model.destroy()
    @model = null
