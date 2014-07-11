DB = {
  get: (name) ->
    data = localStorage['recentPaths']
    data = if data? then JSON.parse(data) else {}
    return data[name]
  set: (name, value) ->
    data = localStorage['recentPaths']
    data = if data? then JSON.parse(data) else {}
    data[name] = value
    localStorage['recentPaths'] = JSON.stringify(data)
}


  


module.exports =
  configDefaults:
    maxRecentDirectories: 10

  handleStorage: (e) ->
    if e.key is "recentPaths"
      @update()

  activate: ->
    @maxRecentDirectories = atom.config.get('recent-files.maxRecentDirectories')
    DB.set('paths', []) unless DB.get('paths')
    DB.set('files', []) unless DB.get('files')
  
    @insertCurrentPath()
    @update()
    window.addEventListener "storage", (e) => @handleStorage(e)

  insertCurrentPath: ->
    return unless atom.project.getRootDirectory()

    path = atom.project.getRootDirectory().path
    recentPaths = DB.get('paths')
    maxRecentDirectories = atom.config.get('recent-files.maxRecentDirectories')

    # Remove if already listed
    index = recentPaths.indexOf path
    if index != -1
      recentPaths.splice index, 1

    recentPaths.splice 0, 0, path

    # Limit
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
    for index, path of DB.get('paths')
      openRecentFileHandler = ->
        atom.open { pathsToOpen: [path] }
      atom.workspaceView.on "recent-files:#{index}", openRecentFileHandler
        

  removeListeners: ->
    for index, path of DB.get('paths')
      atom.workspaceView.off "recent-files:#{index}"

  deactivate: ->
    @removeListeners()
