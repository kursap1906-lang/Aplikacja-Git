import { ApiError } from '../http/errors.ts';

export function validateHierarchy(members: readonly { id: string; parentId: string | null }[]): void {
  const parents = new Map(members.map((member) => [member.id, member.parentId]));
  if (parents.size !== members.length) {
    throw new ApiError(400, 'INVALID_TEAM_HIERARCHY', 'Bot nie może występować w hierarchii dwukrotnie.');
  }
  for (const member of members) {
    const seen = new Set([member.id]);
    let parent = member.parentId;
    while (parent !== null) {
      if (!parents.has(parent)) {
        throw new ApiError(400, 'INVALID_TEAM_HIERARCHY', 'Przełożony musi należeć do tego samego zespołu.');
      }
      if (seen.has(parent)) {
        throw new ApiError(400, 'TEAM_HIERARCHY_CYCLE', 'Hierarchia współpracy nie może zawierać cyklu.');
      }
      seen.add(parent);
      parent = parents.get(parent) ?? null;
    }
  }
}
