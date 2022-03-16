module github.com/rgl/linuxkit-vagrant/machinator

require (
	github.com/VictorLowther/simplexml v0.0.0-20180716164440-0bff93621230
	github.com/VictorLowther/wsman v0.0.0-20170302224735-f2a5e756d330
	github.com/digitalocean/go-qemu v0.0.0-20210326154740-ac9e0b687001
	github.com/stmcginnis/gofish v0.12.0
	github.com/tomruk/oui v1.0.0
)

require (
	github.com/VictorLowther/soap v0.0.0-20150314151524-8e36fca84b22 // indirect
	github.com/digitalocean/go-libvirt v0.0.0-20210723161134-761cfeeb5968 // indirect
	github.com/satori/go.uuid v1.2.0 // indirect
	golang.org/x/sys v0.0.0-20220315194320-039c03cc5b86 // indirect
)

replace github.com/VictorLowther/wsman => github.com/rgl/wsman v0.0.1

replace github.com/tomruk/oui => github.com/rgl/oui v1.0.1-0.20210624175153-a4c98e6f25ea

go 1.18
