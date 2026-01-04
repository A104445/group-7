#let blue = rgb("365F91")
#let gray = rgb("808080")
#let light_gray = rgb("A6A6A6")

#let cover(title, authors, string_date) = {
  let render_authors = grid(columns: authors.len(),
                            column-gutter: 15pt,
                            ..authors.map(it => [
                              #text(size:10pt, weight: "bold", it.name) \
                              #text(size: 10pt, it.number)
                            ])
                           )
                           
  {
    set page(paper: "a4", margin: (x: 0cm,y: 0cm))
    
    rect(fill: blue,height: 100%, width:23.3%)
    
    place(bottom + left,dx: 62pt,dy:-40pt, {
      text(weight:"bold", size: 120pt, fill: white, [A])
      text(weight:"bold", size: 120pt, fill: blue, [BD])
    })
  
    {
      set place(top+left, dx: 200pt)
      place(dy: 120pt, image("images/uminho.png", height: 8%))
      place(dy: 200pt, {
        text(size: 10pt, weight: "bold", fill: gray, [Universidade do Minho\ ])
        text(size: 9pt, fill: gray, [Escola de Engenharia\ Mestrado em Engenharia Informática\ ])
      })
      place(dy: 300pt, {
  
        text(size: 20pt, fill: blue, weight: "bold", [Unidade Curricular de \ Administração de Bases de Dados\ ])
        text(size: 10pt, [Ano Letivo de 2025/2026])
      })
      place(dy: 520pt, text(size: 16pt, weight: "bold", title))
      place(dy: 590pt, render_authors)
      
      place(dy: 640pt, text(size: 12pt, string_date))
    }
  }

  {
    
    align(bottom + left, {
      text(size: 16pt, weight: "bold", title)
      v(30pt)
      set text(size: 12pt)
      render_authors
      v(10pt)
      string_date
    })
  }
  
}