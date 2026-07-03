#import "@preview/drafting:0.2.2": margin-note

#let page-left-margin = 2.5cm
#let page-right-margin = 2.5cm
#let note-col-width = 21cm - page-left-margin - page-right-margin

#let todooleg(body) = margin-note(stroke: rgb("#AAAEEE"), margin-right: page-right-margin, page-width: note-col-width)[#par(
  [#text(body, size: 5pt)],
  leading: 0.1em,
)]

#let todoai(body) = margin-note(stroke: rgb("#CC22AA"), margin-right: page-right-margin, page-width: note-col-width)[#par(
  [#text(body, size: 5pt, fill: rgb("#CC22AA"))],
  leading: 0.1em,
)]

#set document(title: "Title")
#set page(margin: (top: 2.5cm, bottom: 2.5cm, left: page-left-margin, right: page-right-margin))
#set text(size: 11pt)

#align(center)[
  #text(size: 18pt, weight: "bold")[Title]

  Author

  #datetime.today().display("[month repr:long] [day], [year]")
]

= Introduction
