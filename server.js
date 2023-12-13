import express from "express"
import mysql from "mysql"

const app = express()
const port = 3000

const db = mysql.createConnection({
	host: 'svc.sel5.cloudtype.app',
    port: 30691 ,
	user: 'root',
	password: 'mysql1234',
	database: 'animedb',
})

db.connect()

app.get('/', (req, res) => {
  res.json({result: '스마트앱프로그래밍 백엔드'})
})

app.get('/anime', (req, res) => {
    const sql = 'select * from anime'
    
      db.query(sql, (err, rows) => {
          if (err) {
              res.json({result: "error"})
              return console.log(err)
          }
          res.json(rows)
      })
  })

app.listen(port, () => {
  console.log(`서버 실행됨 (port ${port})`)
})