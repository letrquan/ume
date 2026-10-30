import QtQuick
import "shapes"
import "shapes/material-shapes.js" as MaterialShapes

// A Material 3 shape (Circle, Cookie9Sided, Sunny, Clover4Leaf, ...) from end-4's
// rounded-polygon library. Changing `shape` morphs smoothly to the new one.
// With Style.shapeStyle "simple" every one is a circle, unless `keep`.
ShapeCanvas {
    property string shape: "Circle"
    property bool keep: false
    roundedPolygon: MaterialShapes["get" + (Style.shapeStyle === "simple" && !keep ? "Circle" : shape)]()
}
