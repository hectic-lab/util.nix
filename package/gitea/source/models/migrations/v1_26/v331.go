// Copyright 2026 The Gitea Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package v1_26

import (
	"code.gitea.io/gitea/modules/timeutil"

	"xorm.io/xorm"
	"xorm.io/xorm/schemas"
)

type HeatmapContribution struct { //revive:disable-line:exported
	ID          int64              `xorm:"pk autoincr"`
	UserID      int64              `xorm:"NOT NULL"`
	RepoID      int64              `xorm:"NOT NULL"`
	CommitSHA   string             `xorm:"VARCHAR(64) NOT NULL"`
	AuthorEmail string             `xorm:"VARCHAR(320) NOT NULL"`
	AuthorUnix  timeutil.TimeStamp `xorm:"NOT NULL"`
	CreatedUnix timeutil.TimeStamp `xorm:"created"`
	UpdatedUnix timeutil.TimeStamp `xorm:"updated"`
}

// TableIndices implements xorm's TableIndices interface.
func (c *HeatmapContribution) TableIndices() []*schemas.Index {
	uniqueContribution := schemas.NewIndex("repo_commit_user", schemas.UniqueType)
	uniqueContribution.AddColumn("repo_id", "commit_sha", "user_id")

	userAuthorRepo := schemas.NewIndex("u_a_r", schemas.IndexType)
	userAuthorRepo.AddColumn("user_id", "author_unix", "repo_id")

	return []*schemas.Index{uniqueContribution, userAuthorRepo}
}

func CreateHeatmapContributionTable(x *xorm.Engine) error {
	_, err := x.SyncWithOptions(xorm.SyncOptions{IgnoreDropIndices: true}, new(HeatmapContribution))
	return err
}
