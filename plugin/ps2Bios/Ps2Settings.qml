import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "ps2Bios"

    StyledText {
        width: parent.width
        text: "Sounds"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "uiSounds"
        label: "Popout and menu sounds"
        description: "Open/close cues for bar popouts, the launcher, settings and other menus"
        defaultValue: true
    }
    ToggleSetting {
        settingKey: "launcherSounds"
        label: "App launcher sounds"
        description: "A tick as the selection moves, a chime when you launch something"
        defaultValue: true
    }
    ToggleSetting {
        settingKey: "workspaceSound"
        label: "Workspace switch sound"
        defaultValue: true
    }
    ToggleSetting {
        settingKey: "windowSound"
        label: "New window sound"
        defaultValue: true
    }
    ToggleSetting {
        settingKey: "lockSounds"
        label: "Lock screen sounds"
        description: "Lock/unlock cues, plus key ticks and the wrong-password bump when the clock scene is on the lock screen"
        defaultValue: true
    }
    SliderSetting {
        settingKey: "volume"
        label: "PS2 cue volume"
        description: "Relative to the DMS notification volume"
        defaultValue: 100
        minimum: 0
        maximum: 150
        unit: "%"
    }

    StyledText {
        width: parent.width
        text: "Startup"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }
    ToggleSetting {
        settingKey: "introEnabled"
        label: "Boot sequence on login"
        description: "Plays once per login session; click or press any key to skip. Replay: dms ipc call ps2bios intro"
        defaultValue: true
    }
    StringSetting {
        settingKey: "introText"
        label: "Boot sequence text"
        description: "Optional text inside the ring; leave empty for none"
        defaultValue: ""
    }

    StyledText {
        width: parent.width
        text: "Crystal clock scene"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SliderSetting {
        settingKey: "fps"
        label: "Frame rate"
        defaultValue: 24
        minimum: 10
        maximum: 60
        unit: " fps"
    }
    SliderSetting {
        settingKey: "renderScale"
        label: "Render resolution"
        description: "Lower is lighter on the GPU; the fog hides it well"
        defaultValue: 50
        minimum: 35
        maximum: 100
        unit: "%"
    }
    SliderSetting {
        settingKey: "orbs"
        label: "Orbs"
        defaultValue: 8
        minimum: 0
        maximum: 12
    }
    SliderSetting {
        settingKey: "grain"
        label: "Film grain"
        defaultValue: 20
        minimum: 0
        maximum: 100
        unit: "%"
    }
    ToggleSetting {
        settingKey: "followTheme"
        label: "Use theme colors"
        description: "Tint prisms and orbs with the active DMS theme instead of the PS2 palette"
        defaultValue: false
    }
    ToggleSetting {
        settingKey: "showClockText"
        label: "Show time and date text"
        defaultValue: false
    }
}
