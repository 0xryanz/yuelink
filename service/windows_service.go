//go:build windows

package main

import (
	"context"
	"log"

	"golang.org/x/sys/windows/svc"
)

const windowsServiceName = "YueLinkServiceHelper"

type yueWindowsService struct {
	configPath string
}

func isWindowsService() (bool, error) {
	return svc.IsWindowsService()
}

func runWindowsService(configPath string) error {
	return svc.Run(windowsServiceName, &yueWindowsService{configPath: configPath})
}

func (m *yueWindowsService) Execute(
	_ []string,
	requests <-chan svc.ChangeRequest,
	changes chan<- svc.Status,
) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}

	cfg, err := loadConfig(m.configPath)
	if err != nil {
		log.Printf("[service] load config failed: %v", err)
		return false, 1
	}
	if err := configureLogging(cfg.HelperLogPath); err != nil {
		log.Printf("[service] configure logging failed: %v", err)
		return false, 1
	}

	rt, err := NewServiceRuntime(cfg)
	if err != nil {
		log.Printf("[service] create runtime failed: %v", err)
		return false, 1
	}

	listener, handler, err := openTransport(rt)
	if err != nil {
		log.Printf("[service] open transport: %v", err)
		return false, 1
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	runDone := make(chan error, 1)
	go func() {
		runDone <- rt.Run(ctx, listener, handler)
	}()

	changes <- svc.Status{
		State:   svc.Running,
		Accepts: svc.AcceptStop | svc.AcceptShutdown,
	}

	for {
		select {
		case req := <-requests:
			switch req.Cmd {
			case svc.Interrogate:
				changes <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending}
				cancel()
				if err := <-runDone; err != nil {
					log.Printf("[service] runtime shutdown failed: %v", err)
					return false, 1
				}
				return false, 0
			default:
				log.Printf("[service] unsupported control request: %v", req.Cmd)
			}
		case err := <-runDone:
			if err != nil {
				log.Printf("[service] runtime exited with error: %v", err)
				return false, 1
			}
			return false, 0
		}
	}
}
