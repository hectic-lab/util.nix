// Copyright 2018 The Gitea Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package activities

import (
	"context"
	"encoding/json"
	"sort"
	"time"

	"code.gitea.io/gitea/models/db"
	"code.gitea.io/gitea/models/organization"
	user_model "code.gitea.io/gitea/models/user"
	"code.gitea.io/gitea/modules/setting"
	"code.gitea.io/gitea/modules/timeutil"
)

// UserHeatmapData represents the data needed to create a heatmap
type UserHeatmapData struct {
	Timestamp     timeutil.TimeStamp `json:"timestamp"`
	Contributions int64              `json:"contributions"`
}

type heatmapPushAction struct {
	Content     string             `xorm:"content"`
	CreatedUnix timeutil.TimeStamp `xorm:"created_unix"`
}

type heatmapPushActionContent struct {
	Commits []*heatmapPushCommit `json:"Commits"`
}

type heatmapPushCommit struct {
	Timestamp time.Time `json:"Timestamp"`
}

// GetUserHeatmapDataByUser returns an array of UserHeatmapData
func GetUserHeatmapDataByUser(ctx context.Context, user, doer *user_model.User) ([]*UserHeatmapData, error) {
	return getUserHeatmapData(ctx, user, nil, doer)
}

// GetUserHeatmapDataByUserTeam returns an array of UserHeatmapData
func GetUserHeatmapDataByUserTeam(ctx context.Context, user *user_model.User, team *organization.Team, doer *user_model.User) ([]*UserHeatmapData, error) {
	return getUserHeatmapData(ctx, user, team, doer)
}

func getUserHeatmapData(ctx context.Context, user *user_model.User, team *organization.Team, doer *user_model.User) ([]*UserHeatmapData, error) {
	hdata := make([]*UserHeatmapData, 0)

	if !ActivityReadable(user, doer) {
		return hdata, nil
	}

	// Group by 15 minute intervals which will allow the client to accurately shift the timestamp to their timezone.
	// The interval is based on the fact that there are timezones such as UTC +5:30 and UTC +12:45.
	groupBy := "created_unix / 900 * 900"
	groupByName := "timestamp" // We need this extra case because mssql doesn't allow grouping by alias
	switch {
	case setting.Database.Type.IsMySQL():
		groupBy = "created_unix DIV 900 * 900"
	case setting.Database.Type.IsMSSQL():
		groupByName = groupBy
	}

	cond, err := ActivityQueryCondition(ctx, GetFeedsOptions{
		RequestedUser:  user,
		RequestedTeam:  team,
		Actor:          doer,
		IncludePrivate: true, // don't filter by private, as we already filter by repo access
		IncludeDeleted: true,
		// * Heatmaps for individual users only include actions that the user themself did.
		// * For organizations actions by all users that were made in owned
		//   repositories are counted.
		OnlyPerformedBy: !user.IsOrganization(),
	})
	if err != nil {
		return nil, err
	}

	cutoff := timeutil.TimeStampNow() - (366+7)*86400
	engine := db.GetEngine(ctx)

	if err := engine.
		Select(groupBy+" AS timestamp, count(user_id) as contributions").
		Table("action").
		Where(cond).
		And("created_unix > ?", cutoff). // (366+7) days to include the first week for the heatmap
		And("op_type != ?", ActionCommitRepo).
		And("op_type != ?", ActionMirrorSyncPush).
		GroupBy(groupByName).
		OrderBy("timestamp").
		Find(&hdata); err != nil {
		return nil, err
	}

	pushActions := make([]*heatmapPushAction, 0)
	if err := engine.
		Table("action").
		Where(cond).
		And("created_unix > ?", cutoff).
		And("(op_type = ? OR op_type = ?)", ActionCommitRepo, ActionMirrorSyncPush).
		Cols("content", "created_unix").
		Find(&pushActions); err != nil {
		return nil, err
	}

	byTimestamp := make(map[timeutil.TimeStamp]*UserHeatmapData, len(hdata))
	for _, item := range hdata {
		byTimestamp[item.Timestamp] = item
	}

	for _, action := range pushActions {
		payload := new(heatmapPushActionContent)
		if err := json.Unmarshal([]byte(action.Content), payload); err != nil || len(payload.Commits) == 0 {
			entry := heatmapEntryForTimestamp(byTimestamp, &hdata, action.CreatedUnix/900*900)
			entry.Contributions++
			continue
		}

		for _, commit := range payload.Commits {
			if commit == nil {
				continue
			}

			commitUnix := timeutil.TimeStamp(commit.Timestamp.Unix())
			if commitUnix <= cutoff {
				continue
			}

			entry := heatmapEntryForTimestamp(byTimestamp, &hdata, commitUnix/900*900)
			entry.Contributions++
		}
	}

	sort.Slice(hdata, func(i, j int) bool {
		return hdata[i].Timestamp < hdata[j].Timestamp
	})

	return hdata, nil
}

func heatmapEntryForTimestamp(byTimestamp map[timeutil.TimeStamp]*UserHeatmapData, hdata *[]*UserHeatmapData, timestamp timeutil.TimeStamp) *UserHeatmapData {
	if entry, ok := byTimestamp[timestamp]; ok {
		return entry
	}

	entry := &UserHeatmapData{Timestamp: timestamp}
	byTimestamp[timestamp] = entry
	*hdata = append(*hdata, entry)
	return entry
}

// GetTotalContributionsInHeatmap returns the total number of contributions in a heatmap
func GetTotalContributionsInHeatmap(hdata []*UserHeatmapData) int64 {
	var total int64
	for _, v := range hdata {
		total += v.Contributions
	}
	return total
}
