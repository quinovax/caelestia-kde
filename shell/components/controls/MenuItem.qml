import QtQuick

QtObject {
    property string text: ""
    property string icon
    property string trailingIcon
    property string activeIcon: icon
    property string activeText: text
    property bool visible: true
    property var value
    /// Second level entries; when non-empty the row opens a flyout.
    property list<QtObject> children: []

    signal clicked
}
