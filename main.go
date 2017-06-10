/*
 * Copyright (c) 2013 IBM Corp.
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *    Seth Hoenig
 *    Allan Stockdill-Mander
 *    Mike Robertson
 */

package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"time"

	config "github.com/aHisayoshiSuehiro/gomqtttest/config"

	MQTT "github.com/eclipse/paho.mqtt.golang"
)

func NewTLSConfig() *tls.Config {
	// Import trusted certificates from CAfile.pem.
	// Alternatively, manually add CA certificates to
	// default openssl CA bundle.
	certpool := x509.NewCertPool()
	pemCerts, err := ioutil.ReadFile("samplecerts/CAfile.pem")
	if err == nil {
		certpool.AppendCertsFromPEM(pemCerts)
	}

	// Import client certificate/key pair
	cert, err := tls.LoadX509KeyPair("samplecerts/akatsuka.crt", "samplecerts/akatsuka.key")
	if err != nil {
		panic(err)
	}

	// Just to print out the client certificate..
	cert.Leaf, err = x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		panic(err)
	}
	// fmt.Println(cert.Leaf)
	fmt.Println(cert.Leaf.Subject.CommonName)
	// cert := tlsconfig.PeerCertificates[0]

	// Create tls.Config with desired tls properties
	return &tls.Config{
		// RootCAs = certs used to verify server cert.
		RootCAs: certpool,
		// ClientAuth = whether to request cert from server.
		// Since the server is set up for SSL, this happens
		// anyways.
		ClientAuth: tls.NoClientCert,
		// ClientCAs = certs used to validate client cert.
		ClientCAs: nil,
		// InsecureSkipVerify = verify that cert contents
		// match server. IP matches what is in cert etc.
		InsecureSkipVerify: true,
		// Certificates = list of certs client sends to server.
		Certificates: []tls.Certificate{cert},
	}
}

var f MQTT.MessageHandler = func(client MQTT.Client, msg MQTT.Message) {
	go func() {
		fmt.Printf("TOPIC: %s\n", msg.Topic())
		fmt.Printf("MSG: %s\n", msg.Payload())
	}()
}

func main() {
	tlsconfig := NewTLSConfig()
	conf, err := config.GetConfig()
	if err != nil {

	}
	opts := MQTT.NewClientOptions()
	opts.AddBroker("ssl://localhost:8883")
	clientID := tlsconfig.Certificates[0].Leaf.Subject.CommonName
	text := fmt.Sprintf("{\"name\":\"%s\"}", clientID)
	opts.SetClientID(clientID).SetTLSConfig(tlsconfig)
	opts.SetDefaultPublishHandler(f)
	opts.SetWill(conf.DisconnectTopic, text, 1, false)

	// Start the connection
	c := MQTT.NewClient(opts)
	if token := c.Connect(); token.Wait() && token.Error() != nil {
		panic(token.Error())
	}

	c.Subscribe("/status/akatsuka", 0, nil)
	c.Subscribe(conf.ConnectTopic, 0, nil)
	c.Subscribe("/go-mqtt/sample", 0, nil)
	c.Subscribe("$SYS/broker/clients/connected", 0, nil)

	i := 0
	c.Publish(conf.ConnectTopic, 0, false, text)
	for _ = range time.Tick(time.Duration(1) * time.Second) {
		if i == 5 {
			break
		}
		text := fmt.Sprintf("this is msg #%d!", i)
		c.Publish("/go-mqtt/sample", 0, false, text)
		i++
	}

	time.Sleep(3 * time.Second)

	c.Publish(conf.DisconnectTopic, 1, false, text)
	c.Disconnect(250)
}
