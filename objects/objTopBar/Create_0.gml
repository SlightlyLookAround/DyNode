
active = false;

// Deferred Tab-panel close request (set by buttons whose action must not
// destroy the GUIManager while GUIManager.step() is still iterating it)
panelCloseRequest = false;

layout = {
    fromTop : 100,
    padding : 600,
    paddingH : 50
}

layoutBar = {
    w : 300,
    h : 35
}

layoutCheckbox = {
    l : 30
}