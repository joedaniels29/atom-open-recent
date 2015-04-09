path = require('path')

#--- Util Functions
camelCase = (input) ->
  input.toLowerCase().replace /-(.)/g, (match, group1) -> group1.toUpperCase()

#--- localStorage DB
class AtomDB
  constructor: (@key) ->
  getData: ->
    data = localStorage[@key]
    data = if data? then JSON.parse(data) else {}
    return data
  setData: (data) ->
    localStorage[@key] = JSON.stringify(data)
  get: (name) ->
    data = @getData()
    return data[name]
  set: (name, value) ->
    data = @getData()
    data[name] = value
    @setData(data)
  setDefaults: (dbDefaults) ->
    for key, value of dbDefaults
      @set(key, value) unless @get(key)

#---
class AtomConfig
  constructor: (@packageKey) ->
  get: (key) ->
    return atom.config.get(@packageKey + '.' + key)
  setDefaults: (configDefaults) ->
    atom.config.setDefaults(@packageKey, configDefaults) if configDefaults

#---
class AtomPackage
  configDefaults: {}
  dbDefaults: {}

  log: ->
    console.log.apply(console, ["[#{@name}]"].concat(Array.prototype.slice.call(arguments)))

  constructor: (@name) ->
    @config = new AtomConfig(@name)
    @db = new AtomDB(camelCase(@name))

  _onActivate: (state) ->
    @config.setDefaults(@configDefaults)
    @db.setDefaults(@dbDefaults)
    @onActivate(state)
  _onDeactivate: ->
    @onDeactivate()

  onActivate: (state) ->
  onDeactivate: ->

#---
class OpenRecentPackage extends AtomPackage
  configDefaults:
    maxRecentFiles: 8
    maxRecentDirectories: 8
    replaceNewWindowOnOpenDirectory: true
    replaceProjectOnOpenDirectory: false
    listDirectoriesAddedToProject: false
    pathInSublabel: false

  dbDefaults:
    paths: []
    files: []
    pinnedPaths: []
    pinnedFiles: []

  commandListenerDisposables: []
  eventListenerDisposables: []
  onLocalStorageEventListener: null


  #--- Event Handlers
  onActivate: (state) ->
    # Init
    @updateMenu()
    @addEventListeners()


  onDeactivate: ->
    @removeMenuCommandListeners()
    @removeEventListeners()


  onLocalStorageEvent: (e) ->
    if e.key is @db.key
      @updateMenu()

  
  onUriOpened: ->
    editor = atom.workspace.getActiveEditor()
    filePath = editor?.buffer?.file?.path

    # Ignore anything thats not a file.
    return unless filePath
    return unless filePath.indexOf '://' is -1

    @insertFilePath(filePath) if filePath


  onProjectPathChange: (projectPaths) ->
    @insertCurrentPaths()


  #--- Methods
  buildRecentPathMenuItem: (filepath, pinnedPathList) ->
    menuItem = {}

    # label/sublabel
    if @config.get('pathInSublabel')
      menuItem.label = path.basename(filepath)
      menuItem.sublabel = filepath
      if menuItem.label.length == 0 or menuItem.label == '"'
        # Eg: path.basename('C:\') == ''
        # Eg: path.basename('C:\"') == '"'
        menuItem.label = filepath
        menuItem.sublabel = filepath
    else
      menuItem.label = filepath

    # Pinned
    if filepath in pinnedPathList
      menuItem.type = "radio"
      menuItem.checked = true

    return menuItem

  buildPinSubmenu: ->
    submenu = []

    pinnedDirectories = @db.get('pinnedPaths')
    projectDirectories = atom.project.getDirectories()
    if projectDirectories.length > 0
      if projectDirectories[0].path not in pinnedDirectories
        submenu.push { command: "open-recent:pin-project-path", label: projectDirectories[0].path }

    return submenu

  buildUnpinSubmenu: ->
    submenu = []

    # Files
    pinnedFiles = @db.get('pinnedFiles')
    if pinnedFiles.length
      for index, filepath of pinnedFiles
        submenu.push { command: "open-recent:unpin-recent-file-#{index}", label: filepath }
      submenu.push { type: "separator" }

    # Directories
    pinnedDirectories = @db.get('pinnedPaths')
    if pinnedDirectories.length
      for index, filepath of pinnedDirectories
        submenu.push { command: "open-recent:unpin-recent-path-#{index}", label: filepath }
      submenu.push { type: "separator" }

    #
    submenu.push { command: "open-recent:unpin-all", label: "Unpin All" }
    return submenu


  buildOpenRecentSubmenu: ->
    submenu = []
    submenu.push { command: "pane:reopen-closed-item", label: "Reopen Closed File" }
    submenu.push { type: "separator" }

    # Files
    recentFiles = @db.get('files')
    pinnedFiles = @db.get('pinnedFiles')
    if recentFiles.length
      for index, filepath of recentFiles
        menuItem = @buildRecentPathMenuItem(filepath, pinnedFiles)
        menuItem.command = "open-recent:open-recent-file-#{index}"
        # menuItem.label = menuItem.command
        submenu.push menuItem
      submenu.push { type: "separator" }

    # Directories
    recentDirectories = @db.get('paths')
    pinnedDirectories = @db.get('pinnedPaths')
    if recentDirectories.length
      for index, filepath of recentDirectories
        menuItem = @buildRecentPathMenuItem(filepath, pinnedDirectories)
        menuItem.command = "open-recent:open-recent-path-#{index}"
        # menuItem.label = menuItem.command
        submenu.push menuItem
      submenu.push { type: "separator" }

    # Pinned
    submenu.push { label: "Pin", submenu: @buildPinSubmenu() }
    submenu.push { label: "Unpin", submenu: @buildUnpinSubmenu() }
    submenu.push { type: "separator" }

    #
    submenu.push { command: "open-recent:clear", label: "Clear List" }
    return submenu


  updateMenu: ->
    console.log('updateMenu')
    @removeMenuCommandListeners()
    # Update menu items
    for menuItem1 in atom.menu.template
      if menuItem1.label is "File" or menuItem1.label is "&File"
        for menuItem2 in menuItem1.submenu
          if menuItem2.command is "pane:reopen-closed-item" or menuItem2.label is "Open Recent"
            delete menuItem2.command
            menuItem2.label = "Open Recent"
            menuItem2.submenu = @buildOpenRecentSubmenu()
            atom.menu.update()
            break
        break
    @addMenuCommandListeners()


  _dbListRemove: (key, value) ->
    list = @db.get(key)

    # Remove if already listed
    index = list.indexOf value
    if index != -1
      list.splice index, 1

    @db.set(key, list)


  unpinFile: (filepath) ->
    @_dbListRemove('pinnedFiles', filepath)
    @updateMenu()


  unpinDirectory: (filepath) ->
    @_dbListRemove('pinnedPaths', filepath)
    @updateMenu()


  getProjectPath: () ->
    return atom.project.getPaths()?[0]

  openFile: (filepath) ->
    atom.workspace.open filepath

  openDirectory: (filepath) ->
    replaceCurrentProject = false
    options = {}

    if not @getProjectPath() and @config.get('replaceNewWindowOnOpenDirectory')
      replaceCurrentProject = true
    else if @getProjectPath() and @config.get('replaceProjectOnOpenDirectory')
      replaceCurrentProject = true

    if replaceCurrentProject
      atom.project.setPaths([filepath])
      if workspaceElement = atom.views.getView(atom.workspace)
        atom.commands.dispatch workspaceElement, 'tree-view:toggle-focus'
    else
      atom.open {
        pathsToOpen: [filepath]
        newWindow: !@config.get('replaceNewWindowOnOpenDirectory')
      }


  insertCurrentPaths: ->
    return unless atom.project.getRootDirectory()

    recentPaths = @db.get('paths')
    for projectDirectory, index in atom.project.getDirectories()
      # Ignore the second, third, ... folders in a project
      continue if index > 0 and not @config.get('listDirectoriesAddedToProject')

      filepath = projectDirectory.path

      # Remove if already listed
      index = recentPaths.indexOf filepath
      if index != -1
        recentPaths.splice index, 1

      recentPaths.splice 0, 0, filepath

      pinnedDirectories = @db.get('pinnedPaths')
      recentPaths.sort (a, b) ->
        return -1 if a in pinnedDirectories and b not in pinnedDirectories
        return 1 if b in pinnedDirectories and a not in pinnedDirectories
        return 0

      # Limit
      maxRecentDirectories = @config.get('maxRecentDirectories')
      numPathsToRemove = recentPaths.length + pinnedDirectories.length - maxRecentDirectories
      if numPathsToRemove > 0
        recentPaths.splice maxRecentDirectories, recentPaths.length - maxRecentDirectories

    @db.set('paths', recentPaths)
    @updateMenu()


  insertFilePath: (filepath) ->
    recentFiles = @db.get('files')

    # Remove if already listed
    index = recentFiles.indexOf filepath
    if index != -1
      recentFiles.splice index, 1

    recentFiles.splice 0, 0, filepath

    pinnedFiles = @db.get('pinnedFiles')
    recentFiles.sort (a, b) ->
      return -1 if a in pinnedFiles and b not in pinnedFiles
      return 1 if b in pinnedFiles and a not in pinnedFiles
      return 0

    # Limit
    maxRecentFiles = @config.get('maxRecentFiles')
    numPathsToRemove = recentFiles.length + pinnedFiles.length - maxRecentFiles
    if numPathsToRemove > 0
      recentFiles.splice maxRecentFiles, numPathsToRemove

    @db.set('files', recentFiles)
    @updateMenu()


  pinProjectPath: ->
    return unless atom.project.getRootDirectory()
    projectPath = @getProjectPath()
    pinnedDirectories = @db.get('pinnedPaths')
    unless projectPath in pinnedDirectories
      # First make sure the path is listed
      @insertCurrentPaths()

      pinnedDirectories.splice 0, 0, projectPath
      @db.set('pinnedPaths', pinnedDirectories)
      @updateMenu()

  unpinProjectPath: ->
    return unless atom.project.getRootDirectory()
    projectPath = @getProjectPath()
    @_dbListRemove('pinnedPaths', projectPath)
    @updateMenu()
  
  #--- Listeners
  addEventListeners: ->
    @eventListenerDisposables.push atom.workspace.onDidOpen @onUriOpened.bind(@)
    @eventListenerDisposables.push atom.project.onDidChangePaths @onProjectPathChange.bind(@)

    # Notify other windows during a setting data in localStorage.
    @onLocalStorageEventListener = @onLocalStorageEvent.bind(@)
    window.addEventListener 'storage', @onLocalStorageEventListener


  removeEventListeners: ->
    for disposable in @eventListenerDisposables
      disposable.dispose()
    @eventListenerDisposables = []

    window.removeEventListener 'storage', @onLocalStorageEventListener


  addMenuCommandListeners: ->
    # open-recent:open-recent-file-#
    for index, filepath of @db.get('files')
      do (filepath) => # Explicit closure
        disposable = atom.commands.add "atom-workspace", "open-recent:open-recent-file-#{index}", =>
          @openFile filepath
        @commandListenerDisposables.push disposable

    # open-recent:open-recent-path-#
    for index, filepath of @db.get('paths')
      do (filepath) => # Explicit closure
        disposable = atom.commands.add "atom-workspace", "open-recent:open-recent-path-#{index}", =>
          @openDirectory filepath
        @commandListenerDisposables.push disposable

    # open-recent:clear
    disposable = atom.commands.add "atom-workspace", "open-recent:clear", =>
      @db.set('files', [])
      @db.set('paths', [])
      @updateMenu()
    @commandListenerDisposables.push disposable

    # open-recent:pin-project-path
    disposable = atom.commands.add "atom-workspace", "open-recent:pin-project-path", =>
      @pinProjectPath()
    @commandListenerDisposables.push disposable

    # open-recent:unpin-project-path
    disposable = atom.commands.add "atom-workspace", "open-recent:unpin-project-path", =>
      @unpinProjectPath()
    @commandListenerDisposables.push disposable

    # open-recent:open-recent-file-#
    for index, filepath of @db.get('pinnedFiles')
      do (filepath) => # Explicit closure
        disposable = atom.commands.add "atom-workspace", "open-recent:unpin-recent-file-#{index}", =>
          @unpinFile filepath
        @commandListenerDisposables.push disposable

    # open-recent:open-recent-path-#
    for index, filepath of @db.get('pinnedPaths')
      do (filepath) => # Explicit closure
        disposable = atom.commands.add "atom-workspace", "open-recent:unpin-recent-path-#{index}", =>
          @unpinDirectory filepath
        @commandListenerDisposables.push disposable

    # open-recent:unpin-all
    disposable = atom.commands.add "atom-workspace", "open-recent:unpin-all", =>
      @db.set('pinnedFiles', [])
      @db.set('pinnedPaths', [])
      @updateMenu()
    @commandListenerDisposables.push disposable


  removeMenuCommandListeners: ->
    for disposable in @commandListenerDisposables
      disposable.dispose()
    @commandListenerDisposables = []

#---
exports.instance = null
exports.activate = (state) ->
  exports.instance = new OpenRecentPackage('open-recent')
  exports.instance._onActivate(state)
exports.deactivate = ->
  exports.instance._onDeactivate()

Object.defineProperty window, 'openRecent', {get: -> exports.instance}
