package main

import (
	"context"
	"crypto/subtle"
	"errors"
	"flag"
	"fmt"
	"os"
	"time"

	"golang.org/x/term"

	"github.com/weexdayend/flowlesshub/services/api/internal/identity"
	"github.com/weexdayend/flowlesshub/services/api/internal/kernel/config"
	"github.com/weexdayend/flowlesshub/services/api/internal/platform/database"
)

// runBootstrapOwner provisions the first organization owner exactly once.
// Passwords are read from a no-echo terminal prompt and are never accepted as flags.
func runBootstrapOwner(arguments []string) error {
	flags := flag.NewFlagSet("bootstrap-owner", flag.ContinueOnError)
	email := flags.String("email", "", "owner email address")
	displayName := flags.String("name", "", "owner display name")
	organizationName := flags.String("organization-name", "", "initial organization display name")
	organizationSlug := flags.String("organization-slug", "", "initial organization URL slug")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 || *email == "" || *displayName == "" || *organizationName == "" || *organizationSlug == "" {
		return errors.New("usage: flowlesshub-api bootstrap-owner --email <email> --name <name> --organization-name <name> --organization-slug <slug>")
	}
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return errors.New("owner bootstrap requires an interactive terminal for no-echo password input")
	}

	fmt.Fprint(os.Stderr, "Owner password (12-128 bytes): ")
	password, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return fmt.Errorf("read owner password: %w", err)
	}
	defer zeroSecret(password)

	fmt.Fprint(os.Stderr, "Confirm password: ")
	confirmation, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return fmt.Errorf("read password confirmation: %w", err)
	}
	defer zeroSecret(confirmation)
	if subtle.ConstantTimeCompare(password, confirmation) != 1 {
		return errors.New("password confirmation does not match")
	}
	zeroSecret(confirmation)

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect to PostgreSQL: %w", err)
	}
	defer pool.Close()

	service, err := identity.NewService(identity.NewPostgresStore(pool), identity.NewDefaultPasswordHasher(), nil)
	if err != nil {
		return fmt.Errorf("initialize identity service: %w", err)
	}
	result, err := service.BootstrapOwner(ctx, identity.BootstrapInput{
		Email:            *email,
		DisplayName:      *displayName,
		OrganizationName: *organizationName,
		OrganizationSlug: *organizationSlug,
		Password:         password,
	})
	if err != nil {
		return err
	}
	fmt.Fprintf(os.Stdout, "Initial owner provisioned. User ID: %s; organization ID: %s; slug: %s\n", result.UserID, result.OrganizationID, *organizationSlug)
	return nil
}

func zeroSecret(value []byte) {
	for index := range value {
		value[index] = 0
	}
}
