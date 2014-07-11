DB = {}
DB.getData = ->
  data = localStorage['recentPaths']
  data = if data? then JSON.parse(data) else {}
  return data
DB.setData = (data) ->
  localStorage['recentPaths'] = JSON.stringify(data)
DB.get = (name) ->
  data = DB.getData()
  return data[name]
DB.set = (name, value) ->
  data = DB.getData()
  data[name] = value
  DB.setData(data)


module.exports =
  configDefaults:
    maxRecentFiles: 8
    maxRecentDirectories: 8

  DB: DB

  handleStorage: (e) ->
    if e.key is "recentPaths"
      @update()

  activate: ->
    # Migrate v0.3.0 -> v1.0.0
    if DB.getData() instanceof Array
      DB.setData({ paths: DB.getData() })

    # Defaults
    DB.set('paths', []) unless DB.get('paths')
    DB.set('files', []) unless DB.get('files')
  
    @insertCurrentPath()
    @update()
    window.addEventListener "storage", (e) => @handleStorage(e)

  insertCurrentPath: ->
    return unless atom.project.getRootDirectory()

    path = atom.project.getRootDirectory().path
    recentPaths = DB.get('paths')

    # Remove if already listed
    index = recentPaths.indexOf path
    if index != -1
      recentPaths.splice index, 1

    recentPaths.splice 0, 0, path

    # Limit
    maxRecentDirectories = atom.config.get('recent-files.maxRecentDirectories')
    if recentPaths.length > maxRecentDirectories
      recentPaths.splice maxRecentDirectories, recentPaths.length - maxRecentDirectories

    DB.set('paths', recentPaths)

  createSubmenu: ->
    submenu = []
    submenu.push { command: "pane:reopen-closed-item", label: "Reopen Closed File" }
    submenu.push { type: "separator" }

    # Files
    recentFiles = DB.get('files')
    if recentFiles.length
      for index, path of recentFiles
        submenu.push { label: path, command: "recent-files:open-recent-file-#{index}" }
      submenu.push { type: "separator" }

    # Root Paths
    recentPaths = DB.get('paths')
    if recentPaths.length
      for index, path of recentPaths
        submenu.push { label: path, command: "recent-files:open-recent-path-#{index}" }
      submenu.push { type: "separator" }

    submenu.push { command: "recent-files:clear", label: "Clear List" }
    return submenu

  updateMenu: ->
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

  update: ->
    @removeListeners()
    @updateMenu()
    @addListeners()


  addListeners: ->
    # recent-files:open-recent-file-#
    for index, path of DB.get('files')
      openRecentFileHandler = ->
        atom.open { pathsToOpen: [path] }
      atom.workspaceView.on "recent-files:open-recent-file-#{index}", openRecentFileHandler

    # recent-files:open-recent-path-#
    for index, path of DB.get('paths')
      openRecentPathHandler = ->
        atom.open { pathsToOpen: [path] }
      atom.workspaceView.on "recent-files:open-recent-path-#{index}", openRecentPathHandler

    # recent-files:clear
    atom.workspaceView.on "recent-files:clear", ->
      DB.set('files', [])
      DB.set('paths', [])

  removeListeners: ->
    for index, path of DB.get('files')
      atom.workspaceView.off "recent-files:open-recent-file-#{index}"
    for index, path of DB.get('paths')
      atom.workspaceView.off "recent-files:open-recent-path-#{index}"
    atom.workspaceView.off "recent-files:clear"

  deactivate: ->
    @removeListeners()
