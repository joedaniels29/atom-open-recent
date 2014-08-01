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


#--- OpenRecent
OpenRecent = ->
  @db = new DB('openRecent')
  return @

#--- OpenRecent: Event Handlers
OpenRecent.prototype.onLocalStorageEvent = (e) ->
  if e.key is @db.key
    @update()

OpenRecent.prototype.onUriOpened = ->
  editor = atom.workspace.getActiveEditor()
  filePath = editor?.buffer?.file?.path

  # Ignore anything thats not a file.
  return unless filePath
  return unless filePath.indexOf '://' is -1

  @insertFilePath(filePath) if filePath

#--- OpenRecent: Listeners
OpenRecent.prototype.addCommandListeners = ->
  #--- Commands
  # open-recent:open-recent-file-#
  for index, path of @db.get('files')
    do (path) => # Explicit closure
      atom.workspaceView.on "open-recent:open-recent-file-#{index}", =>
        @openFile path

  # open-recent:open-recent-path-#
  for index, path of @db.get('paths')
    do (path) => # Explicit closure
      atom.workspaceView.on "open-recent:open-recent-path-#{index}", =>
        @openPath path

  # open-recent:clear
  atom.workspaceView.on "open-recent:clear", =>
    @db.set('files', [])
    @db.set('paths', [])
    @update()


OpenRecent.prototype.openFile = (path) ->
  atom.workspace.open path

OpenRecent.prototype.openPath = (path) ->
  replaceCurrentProject = false

  if not atom.project.path and atom.config.get('open-recent.replaceNewWindowOnOpenDirectory')
    replaceCurrentProject = true
  else if atom.project.path and atom.config.get('open-recent.replaceProjectOnOpenDirectory')
    replaceCurrentProject = true

  if replaceCurrentProject
    atom.project.setPath(path)
    atom.workspaceView.trigger('tree-view:toggle-focus')
  else
    atom.open { pathsToOpen: [path] }

OpenRecent.prototype.addListeners = ->
  #--- Commands
  @addCommandListeners()

  #--- Events
  atom.workspace.on 'uri-opened', @onUriOpened.bind(@)

  # Notify other windows during a setting data in localStorage.
  window.addEventListener "storage", @onLocalStorageEvent.bind(@)

OpenRecent.prototype.removeCommandListeners = ->
  #--- Commands
  for index, path of @db.get('files')
    atom.workspaceView.off "open-recent:open-recent-file-#{index}"
  for index, path of @db.get('paths')
    atom.workspaceView.off "open-recent:open-recent-path-#{index}"
  atom.workspaceView.off "open-recent:clear"

OpenRecent.prototype.removeListeners = ->
  #--- Commands
  @removeCommandListeners()

  #--- Events
  atom.workspaceView.off 'editor:attached'
  window.removeEventListener 'storage', @onLocalStorageEvent.bind(@)

#--- OpenRecent: Methods
OpenRecent.prototype.init = ->
  @addListeners()

  # Defaults
  @db.set('paths', []) unless @db.get('paths')
  @db.set('files', []) unless @db.get('files')

  @insertCurrentPath()
  @update()

OpenRecent.prototype.insertCurrentPath = ->
  return unless atom.project.getRootDirectory()

  path = atom.project.getRootDirectory().path
  recentPaths = @db.get('paths')

  # Remove if already listed
  index = recentPaths.indexOf path
  if index != -1
    recentPaths.splice index, 1

  recentPaths.splice 0, 0, path

  # Limit
  maxRecentDirectories = atom.config.get('open-recent.maxRecentDirectories')
  if recentPaths.length > maxRecentDirectories
    recentPaths.splice maxRecentDirectories, recentPaths.length - maxRecentDirectories

  @db.set('paths', recentPaths)
  @update()

 OpenRecent.prototype.insertFilePath = (path) ->
  recentFiles = @db.get('files')

  # Remove if already listed
  index = recentFiles.indexOf path
  if index != -1
    recentFiles.splice index, 1

  recentFiles.splice 0, 0, path

  # Limit
  maxRecentFiles = atom.config.get('open-recent.maxRecentFiles')
  if recentFiles.length > maxRecentFiles
    recentFiles.splice maxRecentFiles, recentFiles.length - maxRecentFiles

  @db.set('files', recentFiles)
  @update()

#--- OpenRecent: Menu
OpenRecent.prototype.createSubmenu = ->
  submenu = []
  submenu.push { command: "pane:reopen-closed-item", label: "Reopen Closed File" }
  submenu.push { type: "separator" }

  # Files
  recentFiles = @db.get('files')
  if recentFiles.length
    for index, path of recentFiles
      submenu.push { label: path, command: "open-recent:open-recent-file-#{index}" }
    submenu.push { type: "separator" }

  # Root Paths
  recentPaths = @db.get('paths')
  if recentPaths.length
    for index, path of recentPaths
      submenu.push { label: path, command: "open-recent:open-recent-path-#{index}" }
    submenu.push { type: "separator" }

  submenu.push { command: "open-recent:clear", label: "Clear List" }
  return submenu

OpenRecent.prototype.updateMenu = ->
  # Need to place our menu in top section
  for dropdown in atom.menu.template
    if dropdown.label is "File" or dropdown.label is "&File"
      for item in dropdown.submenu
        if item.command is "pane:reopen-closed-item" or item.label is "Open Recent"
          delete item.command
          item.label = "Open Recent"
          item.submenu = @createSubmenu()
          atom.menu.update()
          break # break for item
      break # break for dropdown

#--- OpenRecent:
OpenRecent.prototype.update = ->
  @removeCommandListeners()
  @updateMenu()
  @addCommandListeners()

OpenRecent.prototype.destroy = ->
  @removeListeners()


#--- Module
module.exports =
  configDefaults:
    maxRecentFiles: 8
    maxRecentDirectories: 8
    replaceNewWindowOnOpenDirectory: true
    replaceProjectOnOpenDirectory: false

  model: null

  activate: ->
    atom.config.setDefaults('open-recent', @configDefaults)
    @model = new OpenRecent()
    @model.init()

  deactivate: ->
    @model.destroy()
    @model = null
